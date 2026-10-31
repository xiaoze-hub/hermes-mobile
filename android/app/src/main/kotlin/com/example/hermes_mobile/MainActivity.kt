package com.example.hermes_mobile

import android.app.Activity
import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import android.provider.Settings
import android.speech.RecognizerIntent
import android.speech.RecognitionListener
import android.speech.RecognitionService
import android.speech.SpeechRecognizer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val channelName = "com.hermes.mobile/files"
    private val pickFilesRequest = 4701
    private val speechPermissionRequest = 4703
    private var filePickerResult: MethodChannel.Result? = null
    private var speechResult: MethodChannel.Result? = null
    private var speechRecognizer: SpeechRecognizer? = null
    private var speechServicePackage: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "recognizeSpeech") {
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
                    return@setMethodCallHandler
                }
                if (call.method == "openSpeechServiceSettings") {
                    val packageName = call.argument<String>("packageName")
                        ?: speechServicePackage
                    if (packageName.isNullOrBlank()) {
                        result.error("speech_service_unknown", "找不到语音识别服务", null)
                    } else {
                        try {
                            startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                data = Uri.parse("package:$packageName")
                            })
                            result.success(null)
                        } catch (error: Exception) {
                            result.error("settings_unavailable", "无法打开语音服务设置", error.message)
                        }
                    }
                    return@setMethodCallHandler
                }
                if (call.method == "getAppUpdateInfo") {
                    val versionInfo = packageManager.getPackageInfo(packageName, 0)
                    val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        versionInfo.longVersionCode
                    } else {
                        @Suppress("DEPRECATION") versionInfo.versionCode.toLong()
                    }
                    val updateDir = java.io.File(cacheDir, "updates")
                    updateDir.mkdirs()
                    result.success(mapOf(
                        "version" to (versionInfo.versionName ?: "0.0.0"),
                        "buildNumber" to versionCode,
                        "updateDirectory" to updateDir.absolutePath,
                        "packageName" to packageName
                    ))
                    return@setMethodCallHandler
                }
                if (call.method == "installApk") {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.error("apk_path_missing", "找不到更新安装包", null)
                        return@setMethodCallHandler
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
                        startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                            data = Uri.parse("package:$packageName")
                        })
                        result.success("permission_required")
                        return@setMethodCallHandler
                    }
                    try {
                        val apk = java.io.File(path)
                        if (!apk.isFile || !apk.canonicalPath.startsWith(java.io.File(cacheDir, "updates").canonicalPath + java.io.File.separator)) {
                            result.error("apk_invalid_path", "更新文件路径无效", null)
                            return@setMethodCallHandler
                        }
                        val apkUri = androidx.core.content.FileProvider.getUriForFile(
                            this, "$packageName.fileprovider", apk
                        )
                        startActivity(Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(apkUri, "application/vnd.android.package-archive")
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        })
                        result.success("installer_opened")
                    } catch (error: Exception) {
                        result.error("installer_failed", "无法打开系统安装器", error.message)
                    }
                    return@setMethodCallHandler
                }
                if (call.method == "shareText") {
                    val text = call.argument<String>("text").orEmpty()
                    if (text.isBlank()) {
                        result.error("share_text_empty", "没有可分享的内容", null)
                    } else {
                        startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_TEXT, text)
                        }, "分享 Hermes 回复"))
                        result.success(null)
                    }
                    return@setMethodCallHandler
                }
                if (call.method != "pickFiles") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
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
        super.onDestroy()
    }

    @Deprecated("Deprecated in Android, retained for Flutter permission callback compatibility")
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != speechPermissionRequest) return
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            launchSpeechRecognition()
        } else {
            finishSpeechWithError("microphone_permission_denied", "需要麦克风权限才能进行语音听写")
        }
    }

    @Deprecated("Deprecated in Android, retained for Flutter activity result compatibility")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickFilesRequest) return
        val callback = filePickerResult ?: return
        filePickerResult = null
        if (resultCode != Activity.RESULT_OK || data == null) {
            callback.success(emptyList<Map<String, Any>>())
            return
        }
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
                val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
                    ?: throw IllegalStateException("Unable to read $name")
                mapOf("name" to name, "bytes" to bytes)
            }
            callback.success(files)
        } catch (error: Exception) {
            callback.error("file_read_failed", error.message, null)
        }
    }
}
