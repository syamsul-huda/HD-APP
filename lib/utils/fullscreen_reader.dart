import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Mode layar penuh untuk layar pembaca dokumen.
///
/// Saat aktif: AppBar disembunyikan (oleh layar pemakai), status bar &
/// navigation bar sistem disembunyikan (immersive), dan rotasi landscape
/// diizinkan. Tombol back / tombol keluar mengembalikan ke mode normal.
mixin FullscreenReaderMixin<T extends StatefulWidget> on State<T> {
  bool isFullscreen = false;

  void setFullscreen(bool value) {
    if (value == isFullscreen) return;
    setState(() => isFullscreen = value);
    _applySystemUi(value);
  }

  void toggleFullscreen() => setFullscreen(!isFullscreen);

  static void _applySystemUi(bool fullscreen) {
    if (fullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
          overlays: SystemUiOverlay.values);
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
  }

  @override
  void dispose() {
    if (isFullscreen) _applySystemUi(false);
    super.dispose();
  }

  /// Tombol untuk AppBar actions.
  Widget fullscreenButton({Color color = Colors.white}) {
    return IconButton(
      tooltip: 'Fullscreen',
      icon: Icon(Icons.fullscreen_rounded, color: color),
      onPressed: () => setFullscreen(true),
    );
  }

  /// Bungkus body: menangani tombol back saat fullscreen dan menampilkan
  /// tombol keluar mengambang. [overlay] opsional (mis. indikator halaman).
  Widget fullscreenBody({required Widget child, Widget? overlay}) {
    return PopScope(
      canPop: !isFullscreen,
      onPopInvoked: (didPop) {
        if (!didPop && isFullscreen) setFullscreen(false);
      },
      child: Stack(
        children: [
          Positioned.fill(child: child),
          if (isFullscreen) ...[
            if (overlay != null)
              Positioned(
                left: 12,
                bottom: 12,
                child: SafeArea(child: overlay),
              ),
            Positioned(
              right: 12,
              top: 12,
              child: SafeArea(
                child: Material(
                  color: Colors.black.withOpacity(0.45),
                  shape: const CircleBorder(),
                  child: IconButton(
                    tooltip: 'Exit fullscreen',
                    icon: const Icon(Icons.fullscreen_exit_rounded,
                        color: Colors.white),
                    onPressed: () => setFullscreen(false),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Label kecil semi-transparan (mis. "3 / 10") untuk overlay fullscreen.
  Widget fullscreenBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child:
          Text(text, style: const TextStyle(fontSize: 12, color: Colors.white)),
    );
  }
}
