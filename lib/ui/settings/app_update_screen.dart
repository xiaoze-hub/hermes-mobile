import 'dart:convert';
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

  // 多源候选清单：优先极速 CDN 与国内容灾镜像，最后回退官方直连
  static const List<String> _manifestEndpoints = [
    'https://fastly.jsdelivr.net/gh/xiaoze-hub/hermes-mobile@main/update.json',
    'https://cdn.jsdelivr.net/gh/xiaoze-hub/hermes-mobile@main/update.json',
    'https://ghfast.top/https://github.com/xiaoze-hub/hermes-mobile/releases/latest/download/update.json',
    'https://gh-proxy.com/https://github.com/xiaoze-hub/hermes-mobile/releases/latest/download/update.json',
    'https://ghproxy.net/https://github.com/xiaoze-hub/hermes-mobile/releases/latest/download/update.json',
    'https://gh.ddlc.top/https://github.com/xiaoze-hub/hermes-mobile/releases/latest/download/update.json',
    'https://raw.githubusercontent.com/xiaoze-hub/hermes-mobile/main/update.json',
    'https://github.com/xiaoze-hub/hermes-mobile/releases/latest/download/update.json',
  ];

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 6),
    receiveTimeout: const Duration(minutes: 5),
    headers: const {
      'Accept': 'application/json, text/plain, */*',
      'User-Agent': 'HermesMobileApp/1.0',
    },
  ));

  Map<String, dynamic>? _release;
  String _currentVersion = '读取中';
  String? _apkPath;
  String? _error;
  double? _progress;
  bool _checking = false;
  bool _downloading = false;
  bool _installPermissionRequired = false;
  String _activeSourceLabel = '官方源';

  @override
  void initState() {
    super.initState();
    _checkForUpdate();
  }

  String _getEndpointLabel(String url, int index) {
    if (url.contains('jsdelivr.net')) return '全球 CDN 加速';
    if (url.contains('ghfast.top')) return '镜像源 · Fast';
    if (url.contains('gh-proxy.com')) return '镜像源 · GHProxy';
    if (url.contains('ghproxy.net')) return '镜像源 · ProxyNet';
    if (url.contains('ddlc.top')) return '镜像源 · DDLC';
    if (url.contains('githubusercontent.com')) return 'GitHub Raw';
    return 'GitHub 官方源';
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

      Map<String, dynamic>? manifest;
      String lastErrMsg = '';
      String succeededSource = '';

      for (int i = 0; i < _manifestEndpoints.length; i++) {
        final endpoint = _manifestEndpoints[i];
        final label = _getEndpointLabel(endpoint, i);
        try {
          final response = await _dio.get<dynamic>(
            endpoint,
            options: Options(
              responseType: ResponseType.plain,
              sendTimeout: const Duration(seconds: 4),
              receiveTimeout: const Duration(seconds: 5),
            ),
          );

          if (response.data != null) {
            final raw = response.data.toString().trim();
            if (raw.isNotEmpty && raw.startsWith('{')) {
              final dynamic parsed = jsonDecode(raw);
              if (parsed is Map) {
                manifest = Map<String, dynamic>.from(parsed);
                succeededSource = label;
                break;
              }
            }
          }
        } catch (e) {
          lastErrMsg = e.toString();
        }
      }

      if (manifest == null) {
        throw StateError('无法从所有候选更新源连接获取版本清单，请检查网络设置。\n(调试: $lastErrMsg)');
      }

      final version = manifest['version']?.toString() ?? '';
      final apkUrl = manifest['apkUrl']?.toString() ?? '';
      final digest = manifest['sha256']?.toString().toLowerCase() ?? '';

      if (version.isEmpty || apkUrl.isEmpty || !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
        throw StateError('更新清单数据缺失或 SHA-256 格式不合法。');
      }

      if (!mounted) return;
      setState(() {
        _activeSourceLabel = succeededSource;
        _currentVersion = '${local['version'] ?? '未知'}+${local['buildNumber'] ?? '?'}';
        _release = {
          ...manifest!,
          '_version': version.replaceFirst(RegExp(r'^[vV]'), ''),
          '_apkUrl': apkUrl,
          '_sha256': digest,
          '_updateAvailable': _compareVersions(
                  version.replaceFirst(RegExp(r'^[vV]'), ''),
                  local['version']?.toString() ?? '0.0.0') > 0,
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

      final rawApkUrl = release['_apkUrl'].toString();
      final downloadCandidates = [
        'https://ghfast.top/$rawApkUrl',
        'https://gh-proxy.com/$rawApkUrl',
        'https://ghproxy.net/$rawApkUrl',
        'https://gh.ddlc.top/$rawApkUrl',
        rawApkUrl,
      ];

      bool downloadSuccess = false;
      Object? lastDownloadError;

      for (final candidate in downloadCandidates) {
        try {
          await _dio.download(
            candidate,
            path,
            deleteOnError: true,
            options: Options(
              sendTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(minutes: 5),
            ),
            onReceiveProgress: (received, total) {
              if (mounted) {
                setState(() => _progress = total > 0 ? received / total : null);
              }
            },
          );
          final file = File(path);
          if (await file.exists()) {
            final actual = (await sha256.bind(file.openRead()).first).toString();
            if (actual == release['_sha256']) {
              downloadSuccess = true;
              break;
            } else {
              await file.delete();
            }
          }
        } catch (e) {
          lastDownloadError = e;
        }
      }

      if (!downloadSuccess) {
        throw StateError('安装包校验失败或所有下载镜像均超时：$lastDownloadError');
      }

      if (!mounted) return;
      setState(() => _apkPath = path);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('下载完成，SHA-256 完整性校验通过！'),
          behavior: SnackBarBehavior.floating,
        ),
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
      final result = await _channel.invokeMethod<String>('installApk', {'path': path});
      if (!mounted) return;
      if (result == 'permission_required') {
        setState(() => _installPermissionRequired = true);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('请在系统设置中允许 Hermes 安装应用，然后返回此页点击“安装更新”'),
          duration: Duration(seconds: 6),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() => _error = '拉起安装器失败: ${e.message ?? e.code}');
      }
    }
  }

  String _friendlyError(Object error) {
    if (error is DioException) {
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout) {
        return '连接更新源超时，建议检查网络或切换节点后点右上角重试。';
      }
      return '网络连接异常（${error.message}），请重试。';
    }
    return error is StateError ? error.message : '更新服务暂时不可用，请稍后重试。';
  }

  @override
  Widget build(BuildContext context) {
    final release = _release;
    final available = release?['_updateAvailable'] == true;

    return Scaffold(
      backgroundColor: HermesTheme.background,
      appBar: AppBar(
        title: const Text('App 固件与在线更新'),
        backgroundColor: HermesTheme.surfaceGlass,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 核心版本卡片
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: HermesTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: HermesTheme.border),
              boxShadow: const [
                BoxShadow(color: Color(0x22000000), blurRadius: 10, offset: Offset(0, 4)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: HermesTheme.userBubbleGradient,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.install_mobile_rounded, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Hermes Mobile',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: HermesTheme.textMain),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '当前本地版本: $_currentVersion',
                            style: const TextStyle(fontSize: 12, color: HermesTheme.textMuted),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '重新检查更新',
                      onPressed: _checking || _downloading ? null : _checkForUpdate,
                      icon: _checking
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: HermesTheme.primary),
                            )
                          : const Icon(Icons.refresh_rounded, size: 20, color: HermesTheme.textMain),
                    ),
                  ],
                ),

                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: HermesTheme.danger.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: HermesTheme.danger.withOpacity(0.3)),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: HermesTheme.danger, fontSize: 12, height: 1.4),
                    ),
                  ),
                ],

                if (release != null) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: available ? HermesTheme.warning.withOpacity(0.15) : HermesTheme.accent.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: available ? HermesTheme.warning.withOpacity(0.4) : HermesTheme.accent.withOpacity(0.4),
                          ),
                        ),
                        child: Text(
                          available ? '发现可用新版本: ${release['_version']}' : '当前已是最新稳定版本',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: available ? HermesTheme.warning : HermesTheme.accent,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '节点: $_activeSourceLabel',
                        style: const TextStyle(fontSize: 10, color: HermesTheme.textDim),
                      ),
                    ],
                  ),

                  if (_installPermissionRequired) ...[
                    const SizedBox(height: 8),
                    const Text('完成系统授权后，返回此页重新点击安装更新。', style: TextStyle(color: HermesTheme.textDim, fontSize: 11)),
                  ],

                  if (_downloading) ...[
                    const SizedBox(height: 14),
                    LinearProgressIndicator(
                      value: _progress,
                      color: HermesTheme.accent,
                      backgroundColor: HermesTheme.surfaceLight,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _progress == null ? '正在高速同步 APK...' : '正在下载 ${(100 * _progress!).round()}%',
                      style: const TextStyle(fontSize: 11, color: HermesTheme.textMuted, fontFamily: 'monospace'),
                    ),
                  ],

                  if (!_downloading) ...[
                    const SizedBox(height: 16),
                    if (_apkPath != null)
                      FilledButton.icon(
                        onPressed: _install,
                        icon: const Icon(Icons.install_mobile_rounded, size: 16),
                        label: const Text('安装更新', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        style: FilledButton.styleFrom(
                          backgroundColor: HermesTheme.accent,
                          minimumSize: const Size.fromHeight(40),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      )
                    else if (available)
                      FilledButton.icon(
                        onPressed: _download,
                        icon: const Icon(Icons.download_rounded, size: 16),
                        label: const Text('高速下载新版更新包', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        style: FilledButton.styleFrom(
                          backgroundColor: HermesTheme.primary,
                          minimumSize: const Size.fromHeight(40),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      )
                    else
                      OutlinedButton.icon(
                        onPressed: _download,
                        icon: const Icon(Icons.download_rounded, size: 16),
                        label: const Text('重新下载此版本安装包 (覆盖修复)', style: TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(38),
                          foregroundColor: HermesTheme.textMuted,
                          side: const BorderSide(color: HermesTheme.borderSubtle),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                  ],
                ],
              ],
            ),
          ),

          if (release != null && (release['notes']?.toString().trim().isNotEmpty ?? false)) ...[
            const SizedBox(height: 16),
            const Text('版本升级说明', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: HermesTheme.textMain)),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: HermesTheme.surfaceElevated,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: HermesTheme.borderSubtle),
              ),
              child: SelectableText(
                release['notes'].toString(),
                style: const TextStyle(fontSize: 13, height: 1.5, color: HermesTheme.textMuted),
              ),
            ),
          ],

          const SizedBox(height: 20),
          const Text(
            '说明：在线更新采用多源容灾机制，自动连接最快节点下载 APK，并在本地严格校验 SHA-256 哈希值保证安全。系统拉起安装器若提示“未知应用来源”，请点击允许安装即可平滑升级。',
            style: TextStyle(color: HermesTheme.textDim, fontSize: 11.5, height: 1.45),
          ),
        ],
      ),
    );
  }
}
