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
        _testMessage = "连接成功！读取到 ${sessions.length} 个活跃会话。";
      });
      tempService.dispose();
    } catch (e) {
      setState(() {
        _testSuccess = false;
        _testMessage = "连接失败: $e";
      });
    } finally {
      setState(() => _testing = false);
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
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: HermesTheme.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.hub, color: HermesTheme.primary, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    "远程网关配置",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: HermesTheme.textMain),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18, color: HermesTheme.textMuted),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text("Linux 服务器网关地址 (带端口 9119)", style: TextStyle(fontSize: 12, color: HermesTheme.textMuted)),
              const SizedBox(height: 6),
              TextField(
                controller: _urlController,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  hintText: "http://192.168.1.100:9119 或 Tailscale IP",
                ),
              ),
              const SizedBox(height: 12),
              const Text("网关认证 Token (可选/安全凭证)", style: TextStyle(fontSize: 12, color: HermesTheme.textMuted)),
              const SizedBox(height: 6),
              TextField(
                controller: _tokenController,
                obscureText: true,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  hintText: "若启用了鉴权请输入 Token",
                ),
              ),
              const SizedBox(height: 12),
              if (_testMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _testSuccess ? Colors.green.withOpacity(0.15) : Colors.red.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _testMessage!,
                    style: TextStyle(
                      fontSize: 12,
                      color: _testSuccess ? Colors.greenAccent : Colors.redAccent,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  OutlinedButton(
                    onPressed: _testing ? null : _testConnection,
                    child: _testing
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5))
                        : const Text("测试连接", style: TextStyle(fontSize: 12)),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _save,
                    style: FilledButton.styleFrom(backgroundColor: HermesTheme.primary),
                    child: const Text("保存并重连", style: TextStyle(fontSize: 12)),
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
