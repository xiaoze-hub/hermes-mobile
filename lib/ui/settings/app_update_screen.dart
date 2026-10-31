import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme.dart';

class AppUpdateScreen extends StatefulWidget {
  const AppUpdateScreen({super.key});

  @override
  State<AppUpdateScreen> createState() => _AppUpdateScreenState();
}

class _AppUpdateScreenState extends State<AppUpdateScreen> {
  static const _channel = MethodChannel('com.hermes.mobile/files');
  static const _manifestUrl =
      'https://github.com/xiaoze-hub/hermes-mobile/releases/latest/download/update.json';
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(minutes: 5),
    headers: const {'Accept': 'application/vnd.github+json'},
  ));

  Map<String, dynamic>? _release;
  String _currentVersion = '读取中';
  String? _apkPath;
  String? _error;
  double? _progress;
  bool _checking = false;
  bool _downloading = false;
  bool _installPermissionRequired = false;

  @override
  void initState() {
    super.initState();
    _checkForUpdate();
  }

  Future<void> _checkForUpdate() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _error = null;
      _release = null;
      _apkPath = null;
      _progress = null;
    });
    try {
      final local = Map<String, dynamic>.from(
          await _channel.invokeMethod<Map>('getAppUpdateInfo') ?? {});
      if (!mounted) return;
      setState(() => _currentVersion =
          '${local['version'] ?? '未知'}+${local['buildNumber'] ?? '?'}');
      final response = await _dio.get<Map<String, dynamic>>(
        _manifestUrl,
        options: Options(responseType: ResponseType.json),
      );
      final manifest = response.data;
      if (manifest == null) throw StateError('更新清单格式无效。');
      final version = manifest['version']?.toString() ?? '';
      final apkUrl = manifest['apkUrl']?.toString() ?? '';
      final digest = manifest['sha256']?.toString().toLowerCase() ?? '';
      if (version.isEmpty ||
          apkUrl.isEmpty ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
        throw StateError('更新清单缺少版本、下载地址或有效的 SHA-256。');
      }
      if (!mounted) return;
      setState(() {
        _currentVersion =
            '${local['version'] ?? '未知'}+${local['buildNumber'] ?? '?'}';
        _release = {
          ...manifest,
          '_version': version.replaceFirst(RegExp(r'^[vV]'), ''),
          '_apkUrl': apkUrl,
          '_sha256': digest,
          '_updateAvailable': _compareVersions(
                  version.replaceFirst(RegExp(r'^[vV]'), ''),
                  local['version']?.toString() ?? '0.0.0') >
              0,
        };
      });
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  int _compareVersions(String left, String right) {
    List<int> parse(String value) => RegExp(r'\d+')
        .allMatches(value)
        .map((match) => int.tryParse(match.group(0)!) ?? 0)
        .toList();
    final a = parse(left);
    final b = parse(right);
    for (var i = 0; i < (a.length > b.length ? a.length : b.length); i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }

  Future<void> _download() async {
    final release = _release;
    if (release == null || _downloading) return;
    setState(() {
      _downloading = true;
      _error = null;
      _progress = 0;
    });
    try {
      final local = Map<String, dynamic>.from(
          await _channel.invokeMethod<Map>('getAppUpdateInfo') ?? {});
      final directory = Directory(local['updateDirectory'].toString());
      await directory.create(recursive: true);
      final name = 'hermes-mobile-${release['_version']}.apk';
      final path = '${directory.path}${Platform.pathSeparator}$name';
      await _dio.download(
        release['_apkUrl'].toString(),
        path,
        deleteOnError: true,
        onReceiveProgress: (received, total) {
          if (mounted) {
            setState(() => _progress = total > 0 ? received / total : null);
          }
        },
      );
      final file = File(path);
      final actual = (await sha256.bind(file.openRead()).first).toString();
      if (actual != release['_sha256']) {
        await file.delete();
        throw StateError('安装包校验失败，文件已删除，请稍后重试。');
      }
      if (!mounted) return;
      setState(() => _apkPath = path);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('下载完成，SHA-256 校验通过')),
      );
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _install() async {
    final path = _apkPath;
    if (path == null) return;
    try {
      final result =
          await _channel.invokeMethod<String>('installApk', {'path': path});
      if (!mounted) return;
      if (result == 'permission_required') {
        setState(() => _installPermissionRequired = true);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('请在系统设置中允许 Hermes 安装应用，然后返回此页点“安装更新”。'),
          duration: Duration(seconds: 6),
        ));
      }
    } on PlatformException catch (error) {
      if (mounted) setState(() => _error = error.message ?? '无法启动系统安装器。');
    }
  }

  String _friendlyError(Object error) {
    if (error is DioException) {
      if (error.response?.statusCode == 404) return '暂时没有发布可用版本。';
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout) {
        return '连接更新服务超时，请检查网络后点右上角重试。';
      }
      if (error.response != null) {
        return '更新服务返回错误（${error.response?.statusCode}），请稍后重试。';
      }
      return '无法连接更新服务，请检查 GitHub 网络连接后点右上角重试。';
    }
    return error is StateError ? error.message : '更新失败，请稍后重试。';
  }

  @override
  Widget build(BuildContext context) {
    final release = _release;
    final available = release?['_updateAvailable'] == true;
    return Scaffold(
      appBar: AppBar(title: const Text('App 更新')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: HermesTheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: HermesTheme.surfaceLight),
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: HermesTheme.accent.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(Icons.system_update_alt,
                      color: HermesTheme.accent),
                ),
                const SizedBox(width: 14),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      const Text('Hermes Mobile',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text('当前版本 $_currentVersion',
                          style: const TextStyle(color: HermesTheme.textMuted)),
                    ])),
                IconButton(
                  tooltip: '重新检查',
                  onPressed: _checking || _downloading ? null : _checkForUpdate,
                  icon: _checking
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh),
                ),
              ]),
              const SizedBox(height: 18),
              if (_checking && release == null)
                const LinearProgressIndicator()
              else if (_error != null) ...[
                Text(_error!,
                    style: const TextStyle(color: HermesTheme.warning)),
                const SizedBox(height: 12),
              ],
              if (release != null) ...[
                Text(available ? '发现新版本 ${release['_version']}' : '当前已是最新版本',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
                if (_installPermissionRequired) ...[
                  const SizedBox(height: 8),
                  const Text('完成系统授权后，返回此页重新点击安装更新。',
                      style: TextStyle(color: HermesTheme.textMuted)),
                ],
                if (_downloading) ...[
                  const SizedBox(height: 16),
                  LinearProgressIndicator(value: _progress),
                  const SizedBox(height: 8),
                  Text(_progress == null
                      ? '正在下载…'
                      : '正在下载 ${(100 * _progress!).round()}%'),
                ],
                if (available && !_downloading) ...[
                  const SizedBox(height: 16),
                  if (_apkPath != null)
                    FilledButton.icon(
                      onPressed: _install,
                      icon: const Icon(Icons.install_mobile),
                      label: const Text('安装更新'),
                    )
                  else
                    FilledButton.icon(
                      onPressed: _download,
                      icon: const Icon(Icons.download),
                      label: const Text('下载更新'),
                    ),
                ],
              ],
            ]),
          ),
          if (release != null &&
              (release['notes']?.toString().trim().isNotEmpty ?? false)) ...[
            const SizedBox(height: 20),
            const Text('更新说明',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: HermesTheme.surface,
                  borderRadius: BorderRadius.circular(16)),
              child: SelectableText(
                release['notes'].toString().trim(),
                style:
                    const TextStyle(color: HermesTheme.textMuted, height: 1.5),
              ),
            ),
          ],
          const SizedBox(height: 20),
          const Text(
            '下载后会先校验安装包，再交由 Android 系统安装。系统可能要求确认安装；更新包必须由同一发布签名签署。',
            style: TextStyle(
                color: HermesTheme.textMuted, fontSize: 12, height: 1.5),
          ),
        ],
      ),
    );
  }
}
