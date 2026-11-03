import 'package:flutter/material.dart';
import '../../core/storage.dart';
import '../../core/theme.dart';
import '../../services/hermes_gateway_service.dart';

class GatewayClusterDialog extends StatefulWidget {
  final HermesGatewayService gatewayService;
  final VoidCallback onSwitched;

  const GatewayClusterDialog({
    super.key,
    required this.gatewayService,
    required this.onSwitched,
  });

  @override
  State<GatewayClusterDialog> createState() => _GatewayClusterDialogState();
}

class _GatewayClusterDialogState extends State<GatewayClusterDialog> {
  final HermesStorage _storage = HermesStorage();
  List<GatewayProfile> _profiles = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    final list = await _storage.getGatewayProfiles();
    final currentUrl = widget.gatewayService.serverUrl;
    final currentToken = widget.gatewayService.token;

    // 如果还没有任何配置档案，将当前的作为第一个
    if (list.isEmpty && currentUrl.isNotEmpty) {
      list.add(GatewayProfile(
        id: 'default',
        name: '当前主节点',
        serverUrl: currentUrl,
        token: currentToken,
      ));
      await _storage.saveGatewayProfiles(list);
    }

    if (mounted) {
      setState(() {
        _profiles = list;
        _loading = false;
      });
    }
  }

  Future<void> _addNewProfile() async {
    final nameCtrl = TextEditingController(text: '远程新集群节点');
    final urlCtrl = TextEditingController(text: 'http://');
    final tokenCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: HermesTheme.surfaceElevated,
        title: const Text('添加集群网关节点',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: '节点别名 (如 家中NAS / 云端VPS)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: urlCtrl,
              decoration: const InputDecoration(
                labelText: '网关地址',
                hintText: 'http://192.168.1.100:9119',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: tokenCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Token 凭证 (可选)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: HermesTheme.primary),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存节点'),
          ),
        ],
      ),
    );

    if (confirmed == true && urlCtrl.text.trim().isNotEmpty) {
      final newProfile = GatewayProfile(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: nameCtrl.text.trim().isEmpty ? '集群节点' : nameCtrl.text.trim(),
        serverUrl: urlCtrl.text.trim(),
        token: tokenCtrl.text.trim(),
      );
      _profiles.add(newProfile);
      await _storage.saveGatewayProfiles(_profiles);
      if (mounted) setState(() {});
    }
  }

  Future<void> _switchToProfile(GatewayProfile profile) async {
    await _storage.saveConfig(profile.serverUrl, profile.token);
    widget.gatewayService.updateConfig(profile.serverUrl, profile.token);
    if (!mounted) return;
    Navigator.pop(context);
    widget.onSwitched();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已无缝切换至网关: ${profile.name}'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _deleteProfile(GatewayProfile profile) async {
    _profiles.removeWhere((p) => p.id == profile.id);
    await _storage.saveGatewayProfiles(_profiles);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final currentUrl = widget.gatewayService.serverUrl;

    return AlertDialog(
      backgroundColor: HermesTheme.surfaceElevated,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.dns_rounded,
              color: HermesTheme.primaryLight, size: 20),
          const SizedBox(width: 8),
          const Text('网关集群与节点切换',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: HermesTheme.textMain)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded,
                color: HermesTheme.accent, size: 20),
            tooltip: '添加新网关节点',
            onPressed: _addNewProfile,
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: HermesTheme.primary))
            : _profiles.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text('暂无已保存的集群节点',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: HermesTheme.textMuted)),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: _profiles.length,
                    separatorBuilder: (_, __) =>
                        const Divider(color: HermesTheme.borderSubtle, height: 1),
                    itemBuilder: (ctx, i) {
                      final p = _profiles[i];
                      final isActive = p.serverUrl == currentUrl;

                      return ListTile(
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        leading: Icon(
                          isActive
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_unchecked_rounded,
                          color: isActive
                              ? HermesTheme.accent
                              : HermesTheme.textDim,
                          size: 18,
                        ),
                        title: Text(
                          p.name,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isActive
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isActive
                                ? HermesTheme.accent
                                : HermesTheme.textMain,
                          ),
                        ),
                        subtitle: Text(
                          p.serverUrl,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color: HermesTheme.textDim),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!isActive && _profiles.length > 1)
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded,
                                    size: 16, color: HermesTheme.textDim),
                                onPressed: () => _deleteProfile(p),
                              ),
                          ],
                        ),
                        onTap: () => _switchToProfile(p),
                      );
                    },
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
