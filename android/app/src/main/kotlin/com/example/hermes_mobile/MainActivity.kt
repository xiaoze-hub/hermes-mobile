package com.example.hermes_mobile

import android.app.Activity
import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.net.Uri
import android.os.Bundle
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.provider.Settings
import android.speech.RecognizerIntent
import android.speech.RecognitionListener
import android.speech.RecognitionService
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.os.Vibrator
import android.os.VibrationEffect
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.FileProvider

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Locale

class MainActivity: FlutterActivity(), TextToSpeech.OnInitListener {
    private val channelName = "com.hermes.mobile/files"
    private val pickFilesRequest = 4701
    private val notificationPermissionRequest = 4702
    private val speechPermissionRequest = 4703
    private val takePhotoRequest = 4704
    private val cameraPermissionRequest = 4705

    private var methodChannel: MethodChannel? = null
    private var filePickerResult: MethodChannel.Result? = null
    private var notificationPermissionResult: MethodChannel.Result? = null
    private var speechResult: MethodChannel.Result? = null
    private var cameraResult: MethodChannel.Result? = null
    private var currentPhotoPath: String? = null

    private var speechRecognizer: SpeechRecognizer? = null
    private var speechServicePackage: String? = null

    private var tts: TextToSpeech? = null
    private var ttsReady: Boolean = false

    private val ioExecutor = java.util.concurrent.Executors.newCachedThreadPool { runnable ->
        Thread(runnable).apply {
            isDaemon = true
            priority = Thread.NORM_PRIORITY - 1
            name = "Hermes-IO-Worker"
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        methodChannel = channel

        // 初始化原生 TTS
        try {
            tts = TextToSpeech(applicationContext, this)
        } catch (_: Exception) {}

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "showNotification" -> {
                    val title = call.argument<String>("title") ?: "Hermes Agent"
                    val content = call.argument<String>("content") ?: ""
                    val id = call.argument<Int>("id") ?: 1001
                    showNotification(title, content, id)
                    result.success(true)
                }
                "requestNotificationPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                            notificationPermissionResult = result
                            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), notificationPermissionRequest)
                            return@setMethodCallHandler
                        }
                    }
                    val manager = NotificationManagerCompat.from(this)
                    result.success(manager.areNotificationsEnabled())
                }
                "areNotificationsEnabled" -> {
                    val enabled = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
                    } else {
                        NotificationManagerCompat.from(this).areNotificationsEnabled()
                    }
                    result.success(enabled)
                }
                "openNotificationSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                            putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (_: Exception) {
                        try {
                            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                data = Uri.parse("package:$packageName")
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("settings_failed", e.message, null)
                        }
                    }
                }
                "vibrate" -> {
                    val ms = call.argument<Number>("durationMs")?.toLong() ?: 80L
                    triggerVibration(ms)
                    result.success(true)
                }
                "recognizeSpeech" -> {
                    if (speechResult != null) {
                        result.error("recognizer_busy", "Speech recognizer is already open", null)
                        return@setMethodCallHandler
                    }
                    speechResult = result
                    if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                        requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), speechPermissionRequest)
                    } else {
                        launchSpeechRecognition()
                    }
                }
                "openSpeechServiceSettings" -> {
                    val pkg = call.argument<String>("packageName") ?: speechServicePackage
                    if (pkg.isNullOrBlank()) {
                        result.error("speech_service_unknown", "找不到语音识别服务", null)
                    } else {
                        try {
                            startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                data = Uri.parse("package:$pkg")
                            })
                            result.success(null)
                        } catch (error: Exception) {
                            result.error("settings_unavailable", "无法打开语音服务设置", error.message)
                        }
                    }
                }
                "takePhoto" -> {
                    if (cameraResult != null) {
                        result.error("camera_busy", "相机操作进行中", null)
                        return@setMethodCallHandler
                    }
                    cameraResult = result
                    if (checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
                        requestPermissions(arrayOf(Manifest.permission.CAMERA), cameraPermissionRequest)
                    } else {
                        launchCamera()
                    }
                }
                "speak" -> {
                    val text = call.argument<String>("text") ?: ""
                    val lang = call.argument<String>("lang") ?: "zh"
                    speakText(text, lang, result)
                }
                "stopSpeaking" -> {
                    tts?.stop()
                    result.success(true)
                }
                "isSpeaking" -> {
                    result.success(tts?.isSpeaking ?: false)
                }
                "getAppUpdateInfo" -> {
                    ioExecutor.execute {
                        try {
                            val versionInfo = packageManager.getPackageInfo(packageName, 0)
                            val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                versionInfo.longVersionCode
                            } else {
                                @Suppress("DEPRECATION") versionInfo.versionCode.toLong()
                            }
                            val updateDir = File(cacheDir, "updates")
                            if (!updateDir.exists()) updateDir.mkdirs()
                            runOnUiThread {
                                result.success(mapOf(
                                    "version" to (versionInfo.versionName ?: "0.0.0"),
                                    "buildNumber" to versionCode,
                                    "updateDirectory" to updateDir.absolutePath,
                                    "packageName" to packageName
                                ))
                            }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error("info_error", e.message, null)
                            }
                        }
                    }
                }
                "installApk" -> {
                    val filePath = call.argument<String>("path") ?: call.argument<String>("filePath")
                    if (filePath.isNullOrBlank()) {
                        result.error("invalid_path", "APK 路径不能为空", null)
                        return@setMethodCallHandler
                    }
                    ioExecutor.execute {
                        try {
                            val file = File(filePath)
                            val canonicalPath = file.canonicalPath
                            val expectedDir = File(cacheDir, "updates").canonicalPath
                            if (!canonicalPath.startsWith(expectedDir)) {
                                runOnUiThread {
                                    result.error("security_violation", "安装文件路径不合法", null)
                                }
                                return@execute
                            }
                            if (!file.exists()) {
                                runOnUiThread {
                                    result.error("file_not_found", "安装包文件不存在", null)
                                }
                                return@execute
                            }
                            runOnUiThread {
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                    if (!packageManager.canRequestPackageInstalls()) {
                                        val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                                            data = Uri.parse("package:$packageName")
                                        }
                                        startActivity(intent)
                                        result.success("permission_required")
                                        return@runOnUiThread
                                    }
                                }
                                try {
                                    val uri = FileProvider.getUriForFile(this@MainActivity, "$packageName.fileprovider", file)
                                    val intent = Intent(Intent.ACTION_VIEW).apply {
                                        setDataAndType(uri, "application/vnd.android.package-archive")
                                        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
                                    }
                                    startActivity(intent)
                                    result.success("ok")
                                } catch (e: Exception) {
                                    result.error("install_failed", e.message, null)
                                }
                            }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error("path_error", e.message, null)
                            }
                        }
                    }
                }
                "pickFiles" -> {
                    if (filePickerResult != null) {
                        result.error("picker_busy", "File picker is already open", null)
                        return@setMethodCallHandler
                    }
                    filePickerResult = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "*/*"
                        putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                    }
                    startActivityForResult(intent, pickFilesRequest)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            ttsReady = true
            tts?.language = Locale.CHINESE
            tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) {
                    runOnUiThread { methodChannel?.invokeMethod("onTtsStart", utteranceId) }
                }
                override fun onDone(utteranceId: String?) {
                    runOnUiThread { methodChannel?.invokeMethod("onTtsDone", utteranceId) }
                }
                override fun onError(utteranceId: String?) {
                    runOnUiThread { methodChannel?.invokeMethod("onTtsError", utteranceId) }
                }
            })
        }
    }

    private fun speakText(text: String, lang: String, result: MethodChannel.Result) {
        if (tts == null || !ttsReady) {
            result.error("tts_not_ready", "语音合成引擎未就绪", null)
            return
        }
        val locale = if (lang.startsWith("en", ignoreCase = true)) Locale.US else Locale.CHINESE
        tts?.language = locale
        val utteranceId = "hermes_live_${System.currentTimeMillis()}"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            val params = Bundle()
            params.putString(TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID, utteranceId)
            tts?.speak(text, TextToSpeech.QUEUE_FLUSH, params, utteranceId)
        } else {
            @Suppress("DEPRECATION")
            val params = HashMap<String, String>()
            params[TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID] = utteranceId
            tts?.speak(text, TextToSpeech.QUEUE_FLUSH, params)
        }
        result.success(true)
    }

    private fun launchCamera() {
        ioExecutor.execute {
            try {
                val photoDir = File(cacheDir, "photos")
                if (!photoDir.exists()) photoDir.mkdirs()
                val photoFile = File(photoDir, "IMG_${System.currentTimeMillis()}.jpg")
                currentPhotoPath = photoFile.absolutePath
                val photoUri = FileProvider.getUriForFile(this@MainActivity, "$packageName.fileprovider", photoFile)
                runOnUiThread {
                    val intent = Intent(MediaStore.ACTION_IMAGE_CAPTURE).apply {
                        putExtra(MediaStore.EXTRA_OUTPUT, photoUri)
                        addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    startActivityForResult(intent, takePhotoRequest)
                }
            } catch (e: Exception) {
                runOnUiThread {
                    cameraResult?.error("camera_launch_failed", e.message, null)
                    cameraResult = null
                }
            }
        }
    }

    private fun showNotification(title: String, content: String, notificationId: Int = 1001) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), notificationPermissionRequest)
                return
            }
        }
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
        val channelId = "hermes_tasks_channel"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "Hermes 特工任务与权限提醒",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Hermes 后台任务完成、耗时任务提醒与高危权限确认通知"
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 150, 80, 150)
                setShowBadge(true)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            }
            notificationManager.createNotificationChannel(channel)
        }
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
        )
        val iconRes = if (applicationInfo.icon != 0) applicationInfo.icon else R.mipmap.ic_launcher
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            android.app.Notification.Builder(this, channelId)
        } else {
            @Suppress("DEPRECATION")
            android.app.Notification.Builder(this)
        }
        val notification = builder
            .setContentTitle(title)
            .setContentText(content)
            .setStyle(android.app.Notification.BigTextStyle().bigText(content))
            .setSmallIcon(iconRes)
            .setAutoCancel(true)
            .setPriority(if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) NotificationManager.IMPORTANCE_HIGH else android.app.Notification.PRIORITY_HIGH)
            .setDefaults(android.app.Notification.DEFAULT_ALL)
            .setContentIntent(pendingIntent)
            .build()
        notificationManager.notify(notificationId, notification)
    }

    private fun triggerVibration(durationMs: Long = 80L) {
        val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator?.vibrate(VibrationEffect.createOneShot(durationMs, VibrationEffect.DEFAULT_AMPLITUDE))
        } else {
            @Suppress("DEPRECATION")
            vibrator?.vibrate(durationMs)
        }
    }

    private fun launchSpeechRecognition() {
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            finishSpeechWithError("recognizer_unavailable", "此设备没有可用的语音识别服务")
            return
        }
        speechServicePackage = packageManager.resolveService(
            Intent(RecognitionService.SERVICE_INTERFACE),
            PackageManager.MATCH_DEFAULT_ONLY
        )?.serviceInfo?.packageName
        try {
            val recognizer = SpeechRecognizer.createSpeechRecognizer(this)
            speechRecognizer = recognizer
            recognizer.setRecognitionListener(object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) = Unit
                override fun onBeginningOfSpeech() = Unit
                override fun onRmsChanged(rmsdB: Float) = Unit
                override fun onBufferReceived(buffer: ByteArray?) = Unit
                override fun onEndOfSpeech() = Unit
                override fun onEvent(eventType: Int, params: Bundle?) = Unit

                override fun onError(error: Int) {
                    val (code, message) = when (error) {
                        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS ->
                            "speech_service_permission_denied" to "语音识别服务没有麦克风权限，请为系统语音服务授权后重试"
                        SpeechRecognizer.ERROR_NETWORK,
                        SpeechRecognizer.ERROR_NETWORK_TIMEOUT ->
                            "speech_network_error" to "语音服务网络连接失败，请检查网络后重试"
                        SpeechRecognizer.ERROR_AUDIO ->
                            "speech_audio_error" to "无法读取麦克风，请检查系统麦克风权限"
                        SpeechRecognizer.ERROR_NO_MATCH,
                        SpeechRecognizer.ERROR_SPEECH_TIMEOUT ->
                            "speech_no_match" to "没有听清内容，请靠近麦克风再试一次"
                        SpeechRecognizer.ERROR_RECOGNIZER_BUSY ->
                            "speech_recognizer_busy" to "语音服务正忙，请稍后重试"
                        else -> "speech_recognition_failed" to "语音识别失败，请检查系统语音服务设置后重试"
                    }
                    finishSpeechWithError(code, message)
                }

                override fun onResults(results: Bundle?) {
                    val transcript = results
                        ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                        ?.firstOrNull()
                    finishSpeechWithResult(transcript)
                }

                override fun onPartialResults(partialResults: Bundle?) = Unit
            })
            recognizer.startListening(Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, java.util.Locale.getDefault().toLanguageTag())
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false)
            })
        } catch (error: Exception) {
            finishSpeechWithError("recognizer_unavailable", "无法启动系统语音识别服务", error.message)
        }
    }

    private fun finishSpeechWithResult(transcript: String?) {
        val callback = speechResult
        speechResult = null
        destroySpeechRecognizer()
        callback?.success(transcript)
    }

    private fun finishSpeechWithError(code: String, message: String, details: String? = null) {
        val callback = speechResult
        speechResult = null
        destroySpeechRecognizer()
        callback?.error(code, message, details ?: speechServicePackage)
    }

    private fun destroySpeechRecognizer() {
        speechRecognizer?.destroy()
        speechRecognizer = null
    }

    override fun onDestroy() {
        destroySpeechRecognizer()
        speechResult?.error("activity_closed", "语音输入已关闭", null)
        speechResult = null
        cameraResult?.error("activity_closed", "相机已关闭", null)
        cameraResult = null
        try {
            tts?.stop()
            tts?.shutdown()
        } catch (_: Exception) {}
        tts = null
        try {
            ioExecutor.shutdown()
        } catch (_: Exception) {}
        super.onDestroy()
    }

    @Deprecated("Deprecated in Android, retained for Flutter permission callback compatibility")
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        when (requestCode) {
            speechPermissionRequest -> {
                if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
                    launchSpeechRecognition()
                } else {
                    finishSpeechWithError("microphone_permission_denied", "需要麦克风权限才能进行语音听写")
                }
            }
            notificationPermissionRequest -> {
                val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
                notificationPermissionResult?.success(granted)
                notificationPermissionResult = null
            }
            cameraPermissionRequest -> {
                if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
                    launchCamera()
                } else {
                    cameraResult?.error("camera_permission_denied", "需要相机权限才能拍照", null)
                    cameraResult = null
                }
            }
        }
    }

    @Deprecated("Deprecated in Android, retained for Flutter activity result compatibility")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == takePhotoRequest) {
            val callback = cameraResult ?: return
            cameraResult = null
            if (resultCode != Activity.RESULT_OK) {
                callback.success(null)
                return
            }
            val path = currentPhotoPath
            if (path == null) {
                callback.success(null)
                return
            }
            ioExecutor.execute {
                try {
                    val file = File(path)
                    if (!file.exists() || file.length() == 0L) {
                        runOnUiThread { callback.success(null) }
                        return@execute
                    }
                    val bytes = file.readBytes()
                    runOnUiThread {
                        callback.success(mapOf(
                            "name" to file.name,
                            "bytes" to bytes,
                            "path" to file.absolutePath
                        ))
                    }
                } catch (e: Exception) {
                    runOnUiThread {
                        callback.error("camera_read_failed", e.message, null)
                    }
                }
            }
            return
        }

        if (requestCode != pickFilesRequest) return
        val callback = filePickerResult ?: return
        filePickerResult = null
        if (resultCode != Activity.RESULT_OK || data == null) {
            callback.success(emptyList<Map<String, Any>>())
            return
        }
        ioExecutor.execute {
            try {
                val uris = mutableListOf<Uri>()
                data.clipData?.let { clip ->
                    for (index in 0 until clip.itemCount) uris.add(clip.getItemAt(index).uri)
                }
                data.data?.let { if (!uris.contains(it)) uris.add(it) }
                val files = uris.map { uri ->
                    val name = contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                        val column = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (column >= 0 && cursor.moveToFirst()) cursor.getString(column) else null
                    } ?: "attachment"
                    val bytes = contentResolver.openInputStream(uri)?.buffered()?.use { it.readBytes() }
                        ?: throw IllegalStateException("Unable to read $name")
                    mapOf("name" to name, "bytes" to bytes)
                }
                runOnUiThread {
                    callback.success(files)
                }
            } catch (error: Exception) {
                runOnUiThread {
                    callback.error("file_read_failed", error.message, null)
                }
            }
        }
    }
}
