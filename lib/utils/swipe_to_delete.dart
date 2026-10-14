import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Geser item ke kiri untuk menampilkan tombol "Delete". Menekan tombol
/// memunculkan dialog konfirmasi sebelum [onDelete] dipanggil.
class SwipeToDelete extends StatefulWidget {
  final Widget child;
  final Future<void> Function() onDelete;
  final String confirmTitle;
  final String confirmMessage;
  final String deleteLabel;

  const SwipeToDelete({
    super.key,
    required this.child,
    required this.onDelete,
    required this.confirmTitle,
    required this.confirmMessage,
    this.deleteLabel = 'Delete',
  });

  @override
  State<SwipeToDelete> createState() => _SwipeToDeleteState();
}

class _SwipeToDeleteState extends State<SwipeToDelete>
    with SingleTickerProviderStateMixin {
  static const _actionWidth = 96.0;
  late final _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 200));

  bool get _isOpen => _ctrl.value > 0.5;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _open() => _ctrl.animateTo(1, curve: Curves.easeOut);
  void _close() => _ctrl.animateTo(0, curve: Curves.easeOut);

  void _onDragUpdate(DragUpdateDetails d) {
    _ctrl.value =
        (_ctrl.value - d.primaryDelta! / _actionWidth).clamp(0.0, 1.0);
  }

  void _onDragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (v < -300) {
      _open();
    } else if (v > 300) {
      _close();
    } else {
      _ctrl.value > 0.5 ? _open() : _close();
    }
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.delete_outline_rounded,
            color: Colors.redAccent, size: 32),
        title: Text(widget.confirmTitle),
        content: Text(widget.confirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(widget.deleteLabel),
          ),
        ],
      ),
    );
    if (ok == true) {
      await widget.onDelete();
    } else if (mounted) {
      _close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: Stack(
        children: [
          // Tombol Delete di belakang item
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerRight,
              child: FadeTransition(
                opacity: _ctrl,
                child: SizedBox(
                  width: _actionWidth - 8,
                  child: Material(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                      onTap: _confirmDelete,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.delete_rounded, color: Colors.white),
                          const SizedBox(height: 4),
                          Text(widget.deleteLabel,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Item yang digeser
          AnimatedBuilder(
            animation: _ctrl,
            builder: (_, child) => Transform.translate(
              offset: Offset(-_ctrl.value * _actionWidth, 0),
              child: child,
            ),
            // Saat terbuka, tap pada item hanya menutup (tidak membuka item)
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (_, child) => _isOpen
                  ? GestureDetector(
                      onTap: _close,
                      behavior: HitTestBehavior.opaque,
                      child: AbsorbPointer(child: child),
                    )
                  : child!,
              child: widget.child,
            ),
          ),
        ],
      ),
    );
  }
}

/// Dialog konfirmasi umum (mis. "Clear all history").
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok == true;
}
