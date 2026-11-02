import 'package:flutter/material.dart';
import '../../core/storage.dart';
import '../../core/theme.dart';
import '../../services/hermes_gateway_service.dart';

class GatewaySettingsDialog extends StatefulWidget {
  final HermesGatewayService gatewayService;
  final VoidCallback onSaved;

  const GatewaySettingsDialog({
    super.key,
    required this.gatewayService,
    required this.onSaved,
  });

  @override
  State<GatewaySettingsDialog> createState() => _GatewaySettingsDialogState();
}

class _GatewaySettingsDialogState extends State<GatewaySettingsDialog> {
  final _urlController = TextEditingController();
  final _tokenController = TextEditingController();
  final _storage = HermesStorage();
  bool _testing = false;
  String? _testMessage;
  bool _testSuccess = false;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    final cfg = await _storage.loadConfig();
    setState(() {
      _urlController.text = cfg.serverUrl;
      _tokenController.text = cfg.token;
    });
  }

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _testMessage = null;
    });

    try {
      final tempService = HermesGatewayService(
        serverUrl: _urlController.text.trim(),
        token: _tokenController.text.trim(),
      );
      final sessions = await tempService.getSessions();
      setState(() {
        _testSuccess = true;
        _testMessage = "通信正常！成功探测到 ${sessions.length} 个远端会话。";
      });
      tempService.dispose();
    } catch (e) {
      setState(() {
        _testSuccess = false;
        _testMessage = "连接失败: $e";
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    final url = _urlController.text.trim();
    final token = _tokenController.text.trim();

    await _storage.saveConfig(url, token);
    widget.gatewayService.updateConfig(url, token);
    widget.onSaved();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: HermesTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: HermesTheme.borderSubtle, width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: HermesTheme.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.settings_ethernet_rounded, color: HermesTheme.primary, size: 18),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    "远程 Linux 网关中控配置",
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: HermesTheme.textMain),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18, color: HermesTheme.textDim),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text("Linux 服务器网关地址 (带端口 9119)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: HermesTheme.textMuted)),
              const SizedBox(height: 6),
              TextField(
                controller: _urlController,
                style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                decoration: const InputDecoration(
                  hintText: "http://192.168.1.100:9119 或 Tailscale IP",
                ),
              ),
              const SizedBox(height: 14),
              const Text("安全认证 Token (可选)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: HermesTheme.textMuted)),
              const SizedBox(height: 6),
              TextField(
                controller: _tokenController,
                obscureText: true,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  hintText: "若服务器开启了 Token 鉴权请输入",
                ),
              ),
              const SizedBox(height: 14),
              if (_testMessage != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _testSuccess ? HermesTheme.accent.withOpacity(0.12) : HermesTheme.danger.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _testSuccess ? HermesTheme.accent.withOpacity(0.3) : HermesTheme.danger.withOpacity(0.3),
                    ),
                  ),
                  child: Text(
                    _testMessage!,
                    style: TextStyle(
                      fontSize: 12,
                      color: _testSuccess ? HermesTheme.accent : const Color(0xFFFCA5A5),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _testing ? null : _testConnection,
                    icon: _testing
                        ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5))
                        : const Icon(Icons.network_check_rounded, size: 15),
                    label: const Text("探测连通性", style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: HermesTheme.textMuted,
                      side: const BorderSide(color: HermesTheme.borderSubtle),
                    ),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: HermesTheme.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text("保存并重连", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
