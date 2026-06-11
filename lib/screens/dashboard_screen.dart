import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/update_service.dart';
import 'home_screen.dart';
import 'reader_screen.dart';
import 'scanner_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkUpdate());
  }

  Future<void> _checkUpdate() async {
    final update = await UpdateService.checkForUpdate();
    if (update == null || !mounted) return;
    _showUpdateDialog(update);
  }

  void _showUpdateDialog(UpdateInfo update) {
    double progress = 0;
    bool downloading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E2640),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.system_update, color: Color(0xFF7B8BFF)),
              SizedBox(width: 8),
              Text('Update Tersedia', style: TextStyle(color: Colors.white)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Versi ${update.version} sudah tersedia.',
                style: const TextStyle(color: Colors.white70),
              ),
              if (update.releaseNotes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  update.releaseNotes,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (downloading) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.white12,
                  color: const Color(0xFF7B8BFF),
                ),
                const SizedBox(height: 4),
                Text(
                  '${(progress * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ],
          ),
          actions: downloading
              ? []
              : [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Nanti', style: TextStyle(color: Colors.white54)),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7B8BFF),
                      foregroundColor: const Color(0xFF1E2640),
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    ),
                    onPressed: () async {
                      setDialogState(() => downloading = true);
                      await UpdateService.downloadAndInstall(
                        update.downloadUrl,
                        (p) => setDialogState(() => progress = p),
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: const Text('Update Sekarang'),
                  ),
                ],
        ),
      ),
    );
  }

  void _showSettings() {
    final api = ApiService();
    final ctrl = TextEditingController(text: api.backendUrl);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2640),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.settings_rounded, color: Color(0xFF7B8BFF), size: 20),
            SizedBox(width: 8),
            Text('Pengaturan', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('URL Backend Server (Video Downloader)',
                style: TextStyle(fontSize: 12, color: Colors.white60)),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                hintText: 'http://192.168.1.x:8000',
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '• Android Emulator: http://10.0.2.2:8000\n'
              '• HP Fisik: http://<IP-Komputer>:8000\n'
              '• iOS Simulator: http://localhost:8000',
              style: TextStyle(fontSize: 11, color: Colors.white38, height: 1.6),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () async {
              await api.setBackendUrl(ctrl.text.trim());
              if (ctx.mounted) Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Backend URL disimpan'),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              );
            },
            style: ElevatedButton.styleFrom(minimumSize: const Size(80, 40)),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF7B8BFF).withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.apps_rounded,
                color: Color(0xFF7B8BFF),
                size: 18,
              ),
            ),
            const SizedBox(width: 8),
            const Text('SuperAppHD'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_rounded, size: 22),
            onPressed: _showSettings,
            tooltip: 'Pengaturan',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pilih Fitur',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Apa yang ingin kamu lakukan?',
              style: TextStyle(fontSize: 13, color: Colors.white38),
            ),
            const SizedBox(height: 24),
            _FeatureCard(
              icon: Icons.download_rounded,
              title: 'Video Downloader',
              description:
                  'Download video dari YouTube, TikTok, Instagram, Facebook, dan 1000+ platform lainnya',
              accentColor: const Color(0xFF7B8BFF),
              tags: const ['YouTube', 'TikTok', 'Instagram', '+1000'],
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HomeScreen()),
              ),
            ),
            const SizedBox(height: 16),
            _FeatureCard(
              icon: Icons.menu_book_rounded,
              title: 'Pembaca Dokumen',
              description:
                  'Buka PDF, Word, Excel, PowerPoint, TXT langsung in-app tanpa aplikasi lain',
              accentColor: const Color(0xFF4ECDC4),
              tags: const ['PDF', 'Word', 'Excel', 'PPT'],
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ReaderScreen()),
              ),
            ),
            const SizedBox(height: 16),
            _FeatureCard(
              icon: Icons.document_scanner_rounded,
              title: 'Scanner Dokumen',
              description:
                  'Scan KTP, ijazah, SIM, sertifikat, dan dokumen lainnya. Simpan sebagai PDF atau JPG',
              accentColor: const Color(0xFFFF6B9D),
              tags: const ['KTP', 'Ijazah', 'SIM', 'Sertifikat'],
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ScannerScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Color accentColor;
  final List<String> tags;
  final VoidCallback onTap;

  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.accentColor,
    required this.tags,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accentColor.withOpacity(0.25), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: accentColor.withOpacity(0.08),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: accentColor, size: 26),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: accentColor.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Buka',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: accentColor,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_forward_rounded, size: 14, color: accentColor),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              description,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.white54,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 6,
              children: tags.map((tag) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    tag,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: accentColor.withOpacity(0.8),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
