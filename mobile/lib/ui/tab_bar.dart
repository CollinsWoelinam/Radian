import 'package:flutter/material.dart';

import 'theme.dart';

enum TabIcon { shift, jobs, history, profile }

class TabItem {
  const TabItem(this.icon, this.label, {this.badge = false});
  final TabIcon icon;
  final String label;

  /// A small dot for something waiting on that tab.
  final bool badge;
}

/// The app's tab bar, styled like the console's nav rail: a sunken strip,
/// the console's stroke icons, and a rounded tile behind the current tab.
/// The Shift tab is the Sweep mark; its vehicle dot turns amber while live.
class RadianTabBar extends StatelessWidget {
  const RadianTabBar({super.key, required this.items, required this.index, required this.onSelect, this.live = false});

  final List<TabItem> items;
  final int index;
  final ValueChanged<int> onSelect;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    // The console's --sunken, --line and --rail-active.
    final sunken = dark ? const Color(0xFF0D1525) : const Color(0xFFEEF2F7);
    final line = dark ? const Color(0x1AFFFFFF) : const Color(0xFFDDE3EC);
    final tile = dark ? const Color(0xFF172238) : const Color(0xFFE8EFFE);
    final scheme = Theme.of(context).colorScheme;
    final accent = dark ? signalBlue : radianBlue;

    return DecoratedBox(
      decoration: BoxDecoration(color: sunken, border: Border(top: BorderSide(color: line))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
          child: Row(children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: _Tab(
                  item: items[i],
                  selected: i == index,
                  onTap: () => onSelect(i),
                  tile: tile,
                  accent: accent,
                  fg: scheme.onSurface,
                  muted: scheme.onSurfaceVariant,
                  ground: sunken,
                  live: live,
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.tile,
    required this.accent,
    required this.fg,
    required this.muted,
    required this.ground,
    required this.live,
  });

  final TabItem item;
  final bool selected;
  final VoidCallback onTap;
  final Color tile, accent, fg, muted, ground;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final color = selected ? accent : muted;
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: 56,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              width: 52,
              height: 32,
              decoration: BoxDecoration(color: selected ? tile : tile.withValues(alpha: 0), borderRadius: BorderRadius.circular(12)),
              child: Center(
                child: CustomPaint(
                  size: const Size.square(22),
                  painter: _IconPainter(
                    item.icon,
                    color: color,
                    ground: selected ? tile : ground,
                    live: live,
                    badge: item.badge ? accent : null,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              item.label,
              style: TextStyle(fontSize: 11.5, height: 1.1, fontWeight: selected ? FontWeight.w600 : FontWeight.w500, color: selected ? fg : muted),
            ),
          ]),
        ),
      ),
    );
  }
}

/// The console's icons (web/src/console/ui.tsx) on the same 24-unit grid,
/// 2-unit round strokes.
class _IconPainter extends CustomPainter {
  _IconPainter(this.icon, {required this.color, required this.ground, required this.live, this.badge});

  final TabIcon icon;
  final Color color;
  final Color ground;
  final bool live;
  final Color? badge;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;

    switch (icon) {
      case TabIcon.shift:
        // The Sweep filling the grid: origin (3.5, 19), radius 17, one radian.
        const vehicle = Offset(12.69, 4.7);
        final wedge = Path()
          ..moveTo(3.5, 19)
          ..lineTo(20.5, 19)
          ..arcToPoint(vehicle, radius: const Radius.circular(17), clockwise: false)
          ..close();
        canvas.drawPath(wedge, Paint()..color = color.withValues(alpha: 0.18));
        canvas.drawPath(wedge, stroke);
        canvas.drawCircle(vehicle, 4.6, Paint()..color = ground);
        canvas.drawCircle(vehicle, 3.3, Paint()..color = live ? liveAmber : color);
      case TabIcon.jobs:
        canvas.drawRRect(RRect.fromLTRBR(3, 4, 21, 20, const Radius.circular(3)), stroke);
        canvas.drawPath(
          Path()
            ..moveTo(8, 9)
            ..lineTo(16, 9)
            ..moveTo(8, 13)
            ..lineTo(16, 13)
            ..moveTo(8, 17)
            ..lineTo(13, 17),
          stroke,
        );
      case TabIcon.history:
        // A clock face turning back: the arc stops short of its arrowhead.
        canvas.drawArc(Rect.fromCircle(center: const Offset(12, 12), radius: 8.5), 3.5, 5.2, false, stroke);
        canvas.drawPath(
          Path()
            ..moveTo(3.4, 5.6)
            ..lineTo(4.1, 9.2)
            ..lineTo(7.7, 8.5)
            ..moveTo(12, 8)
            ..lineTo(12, 12.5)
            ..lineTo(15, 14.5),
          stroke,
        );
      case TabIcon.profile:
        canvas.drawCircle(const Offset(12, 8), 3.8, stroke);
        canvas.drawPath(
          Path()
            ..moveTo(4.5, 20.5)
            ..arcToPoint(const Offset(19.5, 20.5), radius: const Radius.circular(7.5)),
          stroke,
        );
    }

    final b = badge;
    if (b != null) {
      canvas.drawCircle(const Offset(20.5, 3.5), 4, Paint()..color = ground);
      canvas.drawCircle(const Offset(20.5, 3.5), 2.8, Paint()..color = b);
    }
  }

  @override
  bool shouldRepaint(_IconPainter old) => old.icon != icon || old.color != color || old.ground != ground || old.live != live || old.badge != badge;
}
