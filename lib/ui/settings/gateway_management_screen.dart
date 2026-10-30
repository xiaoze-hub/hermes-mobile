import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../services/hermes_gateway_service.dart';

class GatewayManagementScreen extends StatefulWidget {
  final HermesGatewayService gateway;
  const GatewayManagementScreen({super.key, required this.gateway});
  @override
  State<GatewayManagementScreen> createState() =>
      _GatewayManagementScreenState();
}

class _GatewayManagementScreenState extends State<GatewayManagementScreen> {
  Map<String, dynamic> _info = {};
  Map<String, dynamic> _options = {};
  Map<String, dynamic> _update = {};
  bool _loading = true;
  bool _working = false;
  String? _error;
  String _notice = '';
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await Future.wait([
        widget.gateway.getModelInfo(),
        widget.gateway.getModelOptions(),
        widget.gateway.checkForUpdate()
      ]);
      if (!mounted) return;
      setState(() {
        _info = values[0];
        _options = values[1];
        _update = values[2];
        _loading = false;
      });
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e.toString();
          _loading = false;
        });
    }
  }

  List<Map<String, dynamic>> get _models {
    final providers = _options['providers'];
    if (providers is! List) return [];
    return providers.whereType<Map>().expand((p) {
      final provider = p['slug']?.toString() ?? p['name']?.toString() ?? '';
      final models = p['models'];
      if (models is! List) return <Map<String, dynamic>>[];
      return models.map<Map<String, dynamic>>((m) => {
            'provider': provider,
            'model': m is Map
                ? (m['id'] ?? m['model'] ?? m['name']).toString()
                : m.toString(),
            'label': m is Map
                ? (m['name'] ?? m['id'] ?? m['model']).toString()
                : m.toString()
          });
    }).toList();
  }

  Future<void> _switchModel(Map<String, dynamic> item) async {
    setState(() => _working = true);
    try {
      await widget.gateway.setModel(
          provider: item['provider'].toString(),
          model: item['model'].toString());
      if (mounted) {
        setState(() {
          _notice = '模型已切换';
          _working = false;
        });
        await _refresh();
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _notice = '切换失败：$e';
          _working = false;
        });
    }
  }

  Future<bool> _confirm(String title, String detail) async =>
      await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
                title: Text(title),
                content: Text(detail),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('继续'))
                ],
              )) ??
      false;

  Future<void> _runAction({required bool update}) async {
    final ok = await _confirm(
        update ? '升级 Hermes？' : '重启网关？',
        update
            ? '升级会运行 hermes update 并重启网关。期间连接会中断。'
            : '网关将短暂离线，连接的渠道和会话会在服务恢复后重连。');
    if (!ok || !mounted) return;
    setState(() {
      _working = true;
      _notice = update ? '正在检查并升级…' : '正在重启网关…';
    });
    try {
      final response = update
          ? await widget.gateway.updateHermes()
          : await widget.gateway.restartGateway();
      final action = response['action']?.toString() ??
          (update ? 'hermes-update' : 'gateway-restart');
      setState(() => _notice = '操作已启动，正在等待服务恢复…');
      _poll?.cancel();
      int attempt = 0;
      _poll = Timer.periodic(const Duration(seconds: 4), (timer) async {
        attempt++;
        try {
          final status = await widget.gateway.getActionStatus(action);
          final state = (status['status'] ?? status['state'] ?? '')
              .toString()
              .toLowerCase();
          if (state == 'completed' ||
              state == 'success' ||
              state == 'failed' ||
              state == 'error' ||
              attempt >= 20) {
            timer.cancel();
            if (!mounted) return;
            setState(() {
              _working = false;
              _notice = state == 'failed' || state == 'error'
                  ? '操作失败：${status['error'] ?? status['message'] ?? state}'
                  : attempt >= 20 && state != 'completed' && state != 'success'
                      ? '等待超时，请检查网关连接。'
                      : '操作完成，正在刷新状态。';
            });
            await _refresh();
          }
        } catch (_) {
          if (attempt >= 20) {
            timer.cancel();
            if (mounted)
              setState(() {
                _working = false;
                _notice = '等待网关恢复超时，请手动刷新状态。';
              });
          }
        }
      });
    } catch (e) {
      if (mounted)
        setState(() {
          _working = false;
          _notice = '操作失败：$e';
        });
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = _info['model']?.toString() ?? '未知';
    final provider = _info['provider']?.toString() ?? '';
    final current = '$provider/$model';
    final updateAvailable =
        _update['update_available'] == true || _update['available'] == true;
    return Scaffold(
      appBar: AppBar(title: const Text('网关管理'), actions: [
        IconButton(
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh))
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.cloud_off, size: 42),
                        const SizedBox(height: 12),
                        const Text('无法读取网关状态'),
                        Text(_error!,
                            textAlign: TextAlign.center,
                            style:
                                const TextStyle(color: HermesTheme.textMuted)),
                        TextButton(onPressed: _refresh, child: const Text('重试'))
                      ])))
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(padding: const EdgeInsets.all(16), children: [
                    _sectionTitle('运行状态'),
                    Card(
                        child: ListTile(
                            leading: const CircleAvatar(child: Icon(Icons.hub)),
                            title: Text(widget.gateway.connectionStatus ==
                                    ConnectionStatus.connected
                                ? '网关已连接'
                                : 'REST API 可访问'),
                            subtitle: Text(
                                '${widget.gateway.serverUrl}\n当前模型：$current',
                                maxLines: 3),
                            isThreeLine: true,
                            trailing: const Icon(Icons.check_circle,
                                color: HermesTheme.accent))),
                    const SizedBox(height: 20),
                    _sectionTitle('模型'),
                    Card(
                        child: Column(children: [
                      ListTile(
                          leading: const Icon(Icons.auto_awesome),
                          title: const Text('当前模型'),
                          subtitle: Text(current),
                          trailing: const Icon(Icons.expand_more)),
                      const Divider(height: 1),
                      ..._models.take(40).map((item) {
                        final selected =
                            '${item['provider']}/${item['model']}' == current;
                        return ListTile(
                            dense: true,
                            leading: Icon(
                                selected
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
                                color: selected ? HermesTheme.accent : null),
                            title: Text(item['label'].toString()),
                            subtitle: Text(item['provider'].toString()),
                            trailing: selected ? const Text('当前') : null,
                            onTap: _working || selected
                                ? null
                                : () => _switchModel(item));
                      })
                    ])),
                    const SizedBox(height: 20),
                    _sectionTitle('服务维护'),
                    Card(
                        child: Column(children: [
                      ListTile(
                          leading: const Icon(Icons.restart_alt),
                          title: const Text('重启网关'),
                          subtitle: const Text('重连服务与渠道'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _working
                              ? null
                              : () => _runAction(update: false)),
                      const Divider(height: 1),
                      ListTile(
                          leading: const Icon(Icons.system_update_alt),
                          title: const Text('Hermes 更新'),
                          subtitle: Text(updateAvailable
                              ? '发现可用更新'
                              : '当前已是最新版本${_update['current_version'] == null ? '' : ' · ${_update['current_version']}'}'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap:
                              _working ? null : () => _runAction(update: true))
                    ])),
                    if (_notice.isNotEmpty)
                      Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: Text(_notice,
                              style: const TextStyle(
                                  color: HermesTheme.textMuted))),
                    if (_working)
                      const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: LinearProgressIndicator()),
                  ])),
    );
  }

  Widget _sectionTitle(String value) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)));
}
