import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../models/session.dart';

class SessionTabStrip extends StatelessWidget {
  final List<HermesSession> tabs;
  final String activeSessionId;
  final ValueChanged<HermesSession> onSelectTab;
  final ValueChanged<HermesSession> onCloseTab;
  final VoidCallback onNewTab;

  const SessionTabStrip({
    super.key,
    required this.tabs,
    required this.activeSessionId,
    required this.onSelectTab,
    required this.onCloseTab,
    required this.onNewTab,
  });

  @override
  Widget build(BuildContext context) {
    if (tabs.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 38,
      decoration: const BoxDecoration(
        color: Color(0xFF0C101C),
        border: Border(
          bottom: BorderSide(color: HermesTheme.borderSubtle, width: 0.8),
        ),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          if (index == tabs.length) {
            // 新建会话 "+" 按钮
            return InkWell(
              onTap: onNewTab,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: HermesTheme.surfaceLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: HermesTheme.borderSubtle),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded, size: 16, color: HermesTheme.accent),
                    SizedBox(width: 2),
                    Text(
                      '新任务',
                      style: TextStyle(fontSize: 11, color: HermesTheme.accent),
                    ),
                  ],
                ),
              ),
            );
          }

          final session = tabs[index];
          final isActive = session.id == activeSessionId;

          return InkWell(
            onTap: () => onSelectTab(session),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 4, 6, 4),
              decoration: BoxDecoration(
                color: isActive
                    ? const Color(0xFF192238)
                    : HermesTheme.surfaceLight.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isActive
                      ? HermesTheme.primary.withOpacity(0.6)
                      : Colors.transparent,
                  width: 1,
                ),
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: HermesTheme.primary.withOpacity(0.15),
                          blurRadius: 4,
                          spreadRadius: 0.5,
                        )
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isActive
                        ? Icons.terminal_rounded
                        : Icons.chat_bubble_outline_rounded,
                    size: 13,
                    color: isActive
                        ? HermesTheme.accent
                        : HermesTheme.textMuted,
                  ),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 110),
                    child: Text(
                      session.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight:
                            isActive ? FontWeight.bold : FontWeight.normal,
                        color: isActive
                            ? HermesTheme.textMain
                            : HermesTheme.textMuted,
                      ),
                    ),
                  ),
                  if (tabs.length > 1) ...[
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () => onCloseTab(session),
                      borderRadius: BorderRadius.circular(10),
                      child: const Padding(
                        padding: EdgeInsets.all(2),
                        child: Icon(
                          Icons.close_rounded,
                          size: 12,
                          color: HermesTheme.textDim,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
