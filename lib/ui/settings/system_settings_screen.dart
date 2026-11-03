import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/storage.dart';
import '../../core/theme.dart';
import '../../services/hermes_gateway_service.dart';
import 'agent_workspace_screen.dart';
import 'app_update_screen.dart';
import 'gateway_cluster_dialog.dart';
import 'gateway_management_screen.dart';
import 'gateway_settings_dialog.dart';

class SystemSettingsScreen extends StatefulWidget {
  final HermesGatewayService gatewayService;
  final VoidCallback? onConfigChanged;

  const SystemSettingsScreen({
    super.key,
    required this.gatewayService,
    this.onConfigChanged,
  });

  @override
  State<SystemSettingsScreen> createState() => _SystemSettingsScreenState();
}

class _SystemSettingsScreenState extends State<SystemSettingsScreen> {
  final HermesStorage _storage = HermesStorage();

  // 状态变量
  GatewayConfig? _config;
  String _activeProfileName = '默认主节点';
  int _clusterNodeCount = 1;

  bool _tabStripEnabled = true;
  bool _hapticEnabled = true;
  bool _notificationsEnabled = true;
  bool _highRiskApprovalEnabled = true;
  bool _hasSecurityPin = false;

  String _currentVersion = '1.4.0+9';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final cfg = await _storage.loadConfig();
    final profiles = await _storage.getGatewayProfiles();
    final tabStrip = await _storage.getTabStripEnabled();
    final haptic = await _storage.getHapticFeedbackEnabled();
    final notifs = await _storage.getNotificationsEnabled();
    final approval = await _storage.getHighRiskApprovalEnabled();
    final pin = await _storage.getSecurityPin();

    String profileName = '主指令网关';
    for (final p in profiles) {
      if (p.serverUrl == cfg.serverUrl) {
        profileName = p.name;
        break;
      }
    }

    try {
      final info = await const MethodChannel('com.hermes.mobile/files')
          .invokeMethod<Map>('getAppUpdateInfo');
      if (info != null && mounted) {
        _currentVersion = '${info['version'] ?? '1.4.0'}+${info['buildNumber'] ?? '9'}';
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _config = cfg;
      _activeProfileName = profileName;
      _clusterNodeCount = profiles.isEmpty ? 1 : profiles.length;
      _tabStripEnabled = tabStrip;
      _hapticEnabled = haptic;
      _notificationsEnabled = notifs;
      _highRiskApprovalEnabled = approval;
      _hasSecurityPin = pin != null && pin.isNotEmpty;
      _loading = false;
    });
  }

  Future<void> _toggleTabStrip(bool val) async {
    setState(() => _tabStripEnabled = val);
    await _storage.setTabStripEnabled(val);
    widget.onConfigChanged?.call();
  }

  Future<void> _toggleHaptic(bool val) async {
    setState(() => _hapticEnabled = val);
    await _storage.setHapticFeedbackEnabled(val);
  }

  Future<void> _toggleNotifications(bool val) async {
    setState(() => _notificationsEnabled = val);
    await _storage.setNotificationsEnabled(val);
  }

  Future<void> _toggleApproval(bool val) async {
    setState(() => _highRiskApprovalEnabled = val);
    await _storage.setHighRiskApprovalEnabled(val);
  }

  Future<void> _manageSecurityPin() async {
    final pinCtrl = TextEditingController();
    final hasPin = _hasSecurityPin;

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: HermesTheme.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.security_rounded, color: HermesTheme.accent, size: 20),
            const SizedBox(width: 8),
            Text(hasPin ? '管理安全 PIN 锁' : '设置安全 PIN 锁',
                style: const TextStyle(fontSize: 16, color: HermesTheme.textMain)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hasPin ? '当前已设置启动与凭证保护 PIN 码。您可以修改或清除：' : '设置 4-6 位数字 PIN 码以保护网关令牌与敏感配置：',
              style: const TextStyle(fontSize: 12, color: HermesTheme.textMuted),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pinCtrl,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6,
              style: const TextStyle(
                  letterSpacing: 6, fontSize: 18, color: HermesTheme.textMain, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: hasPin ? '输入新 PIN 码' : '设置 PIN 码',
                hintStyle: const TextStyle(letterSpacing: 1, fontSize: 13),
                filled: true,
                fillColor: HermesTheme.surfaceLight,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: HermesTheme.borderSubtle),
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (hasPin)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'clear'),
              child: const Text('清除 PIN', style: TextStyle(color: HermesTheme.danger)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('取消', style: TextStyle(color: HermesTheme.textDim)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: HermesTheme.primary),
            onPressed: () => Navigator.pop(ctx, pinCtrl.text.trim()),
            child: const Text('确定保存', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (action == 'clear') {
      await _storage.setSecurityPin(null);
      setState(() => _hasSecurityPin = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已清除安全 PIN 锁保护')));
      }
    } else if (action != null && action.isNotEmpty) {
      if (action.length < 4) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN 码至少需要 4 位数字')));
        }
        return;
      }
      await _storage.setSecurityPin(action);
      setState(() => _hasSecurityPin = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已成功设置安全 PIN 锁保护')));
      }
    }
  }

  Future<void> _clearCache() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: HermesTheme.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('清理本地缓存', style: TextStyle(fontSize: 16, color: HermesTheme.textMain)),
        content: const Text(
          '将清理临时下载目录中的 APK 安装包文件、会话草稿与图片预览缓存。不会影响远端特工与聊天记录。',
          style: TextStyle(fontSize: 13, color: HermesTheme.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: HermesTheme.textDim)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: HermesTheme.primary),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('立即清理', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    int freedBytes = 0;
    try {
      final info = await const MethodChannel('com.hermes.mobile/files')
          .invokeMethod<Map>('getAppUpdateInfo');
      if (info != null && info['updateDirectory'] != null) {
        final dir = Directory(info['updateDirectory'].toString());
        if (await dir.exists()) {
          await for (final file in dir.list(recursive: true)) {
            if (file is File) {
              freedBytes += await file.length();
              await file.delete();
            }
          }
        }
      }
    } catch (_) {}

    final mb = (freedBytes / (1024 * 1024)).toStringAsFixed(1);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('本地清理完成，共释放 $mb MB 存储空间')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HermesTheme.background,
      appBar: AppBar(
        title: const Text('系统设置与控制中枢', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: HermesTheme.surfaceGlass,
        elevation: 0,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 14, top: 12, bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: HermesTheme.accent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: HermesTheme.accent.withOpacity(0.4)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.bolt_rounded, size: 14, color: HermesTheme.accent),
                SizedBox(width: 4),
                Text('系统就绪', style: TextStyle(fontSize: 11, color: HermesTheme.accent, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: HermesTheme.primary))
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 30),
              children: [
                // 1. 网络与网关集群中枢
                _buildSectionHeader(Icons.hub_rounded, '网络与网关中枢', '管理远程 Linux 特工网关与多节点集群'),
                _buildActiveGatewayCard(),
                const SizedBox(height: 16),

                // 2. 特工与工作区管控
                _buildSectionHeader(Icons.smart_toy_rounded, '特工与工作区管控', '定时计划任务、常驻守护脚本与安全审批'),
                _buildCard([
                  _buildNavTile(
                    icon: Icons.terminal_rounded,
                    title: 'Agent 特工工作台',
                    subtitle: '查看 Linux 系统常驻任务、Cron 定时脚本与工作区',
                    badge: '调度中枢',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AgentWorkspaceScreen(
                            gateway: widget.gatewayService,
                            sessionId: 'workspace-main',
                          ),
                        ),
                      );
                    },
                  ),
                  const Divider(color: HermesTheme.borderSubtle, height: 1),
                  _buildSwitchTile(
                    icon: Icons.shield_rounded,
                    title: '高危命令安全审批',
                    subtitle: '特工执行 rm -rf / 重启 / 端口变更等操作时弹出审批卡片',
                    value: _highRiskApprovalEnabled,
                    onChanged: _toggleApproval,
                  ),
                ]),
                const SizedBox(height: 16),

                // 3. 桌面级交互与偏好设置
                _buildSectionHeader(Icons.desktop_windows_rounded, '桌面级交互偏好', '横向多会话标签栏、触觉震动与通知感知'),
                _buildCard([
                  _buildSwitchTile(
                    icon: Icons.tab_rounded,
                    title: '桌面级横向标签栏',
                    subtitle: '在聊天顶栏显示多会话横向标签栏，支持多任务秒级切换',
                    value: _tabStripEnabled,
                    onChanged: _toggleTabStrip,
                  ),
                  const Divider(color: HermesTheme.borderSubtle, height: 1),
                  _buildSwitchTile(
                    icon: Icons.vibration_rounded,
                    title: '触觉震动反馈',
                    subtitle: '长耗时任务执行完成、收到审批卡片时触发轻量触觉感知',
                    value: _hapticEnabled,
                    onChanged: _toggleHaptic,
                  ),
                  const Divider(color: HermesTheme.borderSubtle, height: 1),
                  _buildSwitchTile(
                    icon: Icons.notifications_active_rounded,
                    title: '系统级审批与完成通知',
                    subtitle: '后台长耗时脚本与命令审批即时拉起 Android 原生状态栏通知',
                    value: _notificationsEnabled,
                    onChanged: _toggleNotifications,
                  ),
                ]),
                const SizedBox(height: 16),

                // 4. 存储、安全与运维清理
                _buildSectionHeader(Icons.storage_rounded, '存储、安全与运维', '安全 PIN 码锁、凭证隔离与本地缓存释放'),
                _buildCard([
                  _buildNavTile(
                    icon: Icons.lock_outline_rounded,
                    title: '安全 PIN 码凭证防护',
                    subtitle: _hasSecurityPin ? '已开启 PIN 码防护（点击可修改或关闭）' : '未开启，建议为网关敏感令牌配置 PIN 保护',
                    badge: _hasSecurityPin ? '已保护' : '未设置',
                    badgeColor: _hasSecurityPin ? HermesTheme.accent : HermesTheme.warning,
                    onTap: _manageSecurityPin,
                  ),
                  const Divider(color: HermesTheme.borderSubtle, height: 1),
                  _buildNavTile(
                    icon: Icons.cleaning_services_rounded,
                    title: '清理本地临时缓存与安装包',
                    subtitle: '安全释放下载的 APK 固件包与图片预览缓存',
                    onTap: _clearCache,
                  ),
                ]),
                const SizedBox(height: 16),

                // 5. 固件在线更新与关于
                _buildSectionHeader(Icons.info_outline_rounded, '系统固件与关于', '在线 OTA 平滑更新与开源工程信息'),
                _buildCard([
                  _buildNavTile(
                    icon: Icons.system_update_alt_rounded,
                    title: 'App 固件与在线更新',
                    subtitle: '当前已就绪版本: $_currentVersion',
                    badge: '检查新版',
                    badgeColor: HermesTheme.primaryLight,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AppUpdateScreen()),
                      );
                    },
                  ),
                  const Divider(color: HermesTheme.borderSubtle, height: 1),
                  _buildNavTile(
                    icon: Icons.code_rounded,
                    title: 'GitHub 开源工程仓库',
                    subtitle: 'github.com/xiaoze-hub/hermes-mobile',
                    onTap: () {
                      Clipboard.setData(
                        const ClipboardData(text: 'https://github.com/xiaoze-hub/hermes-mobile'),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已复制 GitHub 仓库地址至剪贴板')),
                      );
                    },
                  ),
                  const Divider(color: HermesTheme.borderSubtle, height: 1),
                  _buildNavTile(
                    icon: Icons.terminal_outlined,
                    title: '关于 Hermes Mobile 桌面特工',
                    subtitle: '面向 Linux Hermes Agent 的移动端全功能桌面级客户端',
                    onTap: () {
                      showAboutDialog(
                        context: context,
                        applicationName: 'Hermes Mobile',
                        applicationVersion: _currentVersion,
                        applicationLegalese: 'Copyright © 2026 Hermes Team.\nOpen source under MIT License.',
                        children: const [
                          SizedBox(height: 10),
                          Text('全功能对齐桌面端 Agent 特工控制台，支持横向多任务标签、终端直连控制、工作区文件树与会话工件归纳。'),
                        ],
                      );
                    },
                  ),
                ]),
              ],
            ),
    );
  }

  // --- UI 构建组件 ---
  Widget _buildSectionHeader(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: HermesTheme.primaryLight),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: HermesTheme.textMain,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(fontSize: 10.5, color: HermesTheme.textDim)),
        ],
      ),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: HermesTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: HermesTheme.border),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildActiveGatewayCard() {
    final url = _config?.serverUrl ?? '未配置';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF161F36),
            HermesTheme.surface,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: HermesTheme.primary.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  gradient: HermesTheme.userBubbleGradient,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.dns_rounded, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _activeProfileName,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: HermesTheme.textMain),
                    ),
                    Text(
                      url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: HermesTheme.textMuted),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: HermesTheme.accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: HermesTheme.accent.withOpacity(0.3)),
                ),
                child: Text('集群: $_clusterNodeCount 个节点',
                    style: const TextStyle(fontSize: 10, color: HermesTheme.accent)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: HermesTheme.borderSubtle, height: 1),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              TextButton.icon(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => GatewayClusterDialog(
                      gatewayService: widget.gatewayService,
                      onSwitched: () {
                        _loadSettings();
                        widget.onConfigChanged?.call();
                      },
                    ),
                  );
                },
                icon: const Icon(Icons.hub_rounded, size: 15, color: HermesTheme.accent),
                label: const Text('秒级切换节点', style: TextStyle(fontSize: 12, color: HermesTheme.accent)),
              ),
              Container(width: 1, height: 16, color: HermesTheme.borderSubtle),
              TextButton.icon(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => GatewaySettingsDialog(
                      gatewayService: widget.gatewayService,
                      onSaved: () {
                        _loadSettings();
                        widget.onConfigChanged?.call();
                      },
                    ),
                  );
                },
                icon: const Icon(Icons.edit_note_rounded, size: 16, color: HermesTheme.primaryLight),
                label: const Text('参数配置', style: TextStyle(fontSize: 12, color: HermesTheme.primaryLight)),
              ),
              Container(width: 1, height: 16, color: HermesTheme.borderSubtle),
              TextButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => GatewayManagementScreen(gateway: widget.gatewayService),
                    ),
                  ).then((_) => _loadSettings());
                },
                icon: const Icon(Icons.manage_accounts_rounded, size: 16, color: HermesTheme.textMuted),
                label: const Text('节点管理', style: TextStyle(fontSize: 12, color: HermesTheme.textMuted)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNavTile({
    required IconData icon,
    required String title,
    required String subtitle,
    String? badge,
    Color? badgeColor,
    required VoidCallback onTap,
  }) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      leading: Icon(icon, size: 20, color: HermesTheme.primaryLight),
      title: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: HermesTheme.textMain)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 11, color: HermesTheme.textDim)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (badge != null)
            Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: (badgeColor ?? HermesTheme.primary).withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: (badgeColor ?? HermesTheme.primary).withOpacity(0.4)),
              ),
              child: Text(badge, style: TextStyle(fontSize: 10, color: badgeColor ?? HermesTheme.primaryLight)),
            ),
          const Icon(Icons.chevron_right_rounded, size: 18, color: HermesTheme.textDim),
        ],
      ),
      onTap: onTap,
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      secondary: Icon(icon, size: 20, color: HermesTheme.primaryLight),
      title: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: HermesTheme.textMain)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 11, color: HermesTheme.textDim)),
      value: value,
      activeColor: HermesTheme.accent,
      onChanged: onChanged,
    );
  }
}
