import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/app_settings.dart';
import '../services/update_service.dart';
import 'home_screen.dart';
import 'reader_screen.dart';
import 'scanner_screen.dart';

// ── Feature data model ────────────────────────────────────────────────────────
class _Feature {
  final IconData icon;
  final String title;
  final String description;
  final Color accentColor;
  final List<String> tags;
  final VoidCallback onTap;
  const _Feature({
    required this.icon, required this.title, required this.description,
    required this.accentColor, required this.tags, required this.onTap,
  });
}

// ── Dashboard ─────────────────────────────────────────────────────────────────
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

  List<_Feature> _features() => [
        _Feature(
          icon: Icons.download_rounded,
          title: 'Video Downloader',
          description:
              'Download video dari YouTube, TikTok, Instagram, Facebook, dan 1000+ platform lainnya',
          accentColor: const Color(0xFF7B8BFF),
          tags: const ['YouTube', 'TikTok', 'Instagram', '+1000'],
          onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const HomeScreen())),
        ),
        _Feature(
          icon: Icons.menu_book_rounded,
          title: 'Pembaca Dokumen',
          description:
              'Buka PDF, Word, Excel, PowerPoint, TXT langsung in-app tanpa aplikasi lain',
          accentColor: const Color(0xFF4ECDC4),
          tags: const ['PDF', 'Word', 'Excel', 'PPT'],
          onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const ReaderScreen())),
        ),
        _Feature(
          icon: Icons.document_scanner_rounded,
          title: 'Scanner Dokumen',
          description:
              'Scan KTP, ijazah, SIM, sertifikat, dan dokumen lainnya. Simpan sebagai PDF atau JPG',
          accentColor: const Color(0xFFFF6B9D),
          tags: const ['KTP', 'Ijazah', 'SIM', 'Sertifikat'],
          onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const ScannerScreen())),
        ),
      ];

  void _showUpdateDialog(UpdateInfo update) {
    double progress = 0;
    bool downloading = false;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1E2640) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(children: [
              const Icon(Icons.system_update, color: Color(0xFF7B8BFF)),
              const SizedBox(width: 8),
              Text('Update Tersedia',
                  style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                      fontSize: 17)),
            ]),
            content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Versi ${update.version} sudah tersedia.',
                  style: TextStyle(color: isDark ? Colors.white70 : const Color(0xFF555770))),
              if (update.releaseNotes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(update.releaseNotes,
                    style: TextStyle(color: isDark ? Colors.white38 : const Color(0xFF9B9FAD), fontSize: 12),
                    maxLines: 4, overflow: TextOverflow.ellipsis),
              ],
              if (downloading) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: progress,
                  backgroundColor: isDark ? Colors.white12 : const Color(0xFFE4E7F0),
                  color: const Color(0xFF7B8BFF),
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 4),
                Text('${(progress * 100).toStringAsFixed(0)}%',
                    style: TextStyle(color: isDark ? Colors.white54 : const Color(0xFF9B9FAD), fontSize: 12)),
              ],
            ]),
            actions: downloading
                ? []
                : [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text('Nanti',
                          style: TextStyle(
                              color: isDark ? Colors.white38 : const Color(0xFF9B9FAD))),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7B8BFF),
                          foregroundColor: Colors.white,
                          minimumSize: Size.zero,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10)),
                      onPressed: () async {
                        set(() => downloading = true);
                        await UpdateService.downloadAndInstall(
                          update.downloadUrl,
                          (p) => set(() => progress = p),
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      child: const Text('Update Sekarang'),
                    ),
                  ],
          );
        },
      ),
    );
  }

  void _openSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: const _SettingsSheet(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final appBarBg = isDark ? const Color(0xFF1A1E30) : Colors.white;
    final divColor = isDark ? const Color(0xFF2A3050) : const Color(0xFFE4E7F0);
    final iconColor = isDark ? Colors.white70 : const Color(0xFF555770);
    final titleColor = isDark ? Colors.white : const Color(0xFF1A1A2E);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: appBarBg,
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFF7B8BFF).withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.apps_rounded, color: Color(0xFF7B8BFF), size: 18),
          ),
          const SizedBox(width: 8),
          Text('SuperAppHD',
              style: TextStyle(color: titleColor, fontWeight: FontWeight.bold)),
        ]),
        actions: [
          IconButton(
            icon: Icon(Icons.settings_outlined, size: 22, color: iconColor),
            onPressed: _openSettings,
            tooltip: 'Pengaturan',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: divColor),
        ),
      ),
      body: ValueListenableBuilder<String>(
        valueListenable: AppSettings.viewMode,
        builder: (ctx, view, _) => view == 'grid'
            ? _buildGrid(ctx)
            : _buildList(ctx),
      ),
    );
  }

  // ── List view ───────────────────────────────────────────────────────────────
  Widget _buildList(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final textSub = isDark ? const Color(0xFF6B7394) : const Color(0xFF9B9FAD);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Pilih Fitur',
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold, color: textPrimary)),
          const SizedBox(height: 4),
          Text('Apa yang ingin kamu lakukan?',
              style: TextStyle(fontSize: 13, color: textSub)),
          const SizedBox(height: 20),
          ..._features().expand((f) => [
                _FeatureCard(feature: f),
                const SizedBox(height: 14),
              ]),
        ],
      ),
    );
  }

  // ── Grid view ───────────────────────────────────────────────────────────────
  Widget _buildGrid(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final textSub = isDark ? const Color(0xFF6B7394) : const Color(0xFF9B9FAD);
    final features = _features();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Pilih Fitur',
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold, color: textPrimary)),
            const SizedBox(height: 4),
            Text('Apa yang ingin kamu lakukan?',
                style: TextStyle(fontSize: 13, color: textSub)),
          ]),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 0.82,
            ),
            itemCount: features.length,
            itemBuilder: (_, i) => _GridCard(feature: features[i]),
          ),
        ),
      ],
    );
  }
}

// ── Feature card (list view) ──────────────────────────────────────────────────
class _FeatureCard extends StatelessWidget {
  final _Feature feature;
  const _FeatureCard({required this.feature});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E2640) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final textSub = isDark ? const Color(0xFF8892B0) : const Color(0xFF9B9FAD);
    final a = feature.accentColor;

    return GestureDetector(
      onTap: feature.onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: a.withOpacity(0.2), width: 1.5),
          boxShadow: isDark
              ? [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 2))]
              : [
                  BoxShadow(color: a.withOpacity(0.08), blurRadius: 16, offset: const Offset(0, 4)),
                  BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2)),
                ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: a.withOpacity(0.12), borderRadius: BorderRadius.circular(14)),
              child: Icon(feature.icon, color: a, size: 26),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: a.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: a.withOpacity(0.25)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('Buka',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: a)),
                const SizedBox(width: 4),
                Icon(Icons.arrow_forward_rounded, size: 14, color: a),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          Text(feature.title,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: textPrimary)),
          const SizedBox(height: 5),
          Text(feature.description,
              style: TextStyle(fontSize: 13, color: textSub, height: 1.4)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            children: feature.tags.map((tag) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: a.withOpacity(0.08), borderRadius: BorderRadius.circular(6)),
              child: Text(tag,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: a)),
            )).toList(),
          ),
        ]),
      ),
    );
  }
}

// ── Feature card (grid view) ──────────────────────────────────────────────────
class _GridCard extends StatelessWidget {
  final _Feature feature;
  const _GridCard({required this.feature});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E2640) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final a = feature.accentColor;

    return GestureDetector(
      onTap: feature.onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: a.withOpacity(0.2), width: 1.5),
          boxShadow: isDark
              ? [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8)]
              : [BoxShadow(color: a.withOpacity(0.1), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Icon
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: a.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
            child: Icon(feature.icon, color: a, size: 24),
          ),
          const Spacer(),
          // Title
          Text(
            feature.title,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textPrimary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          // Tags (max 2)
          Wrap(
            spacing: 4, runSpacing: 4,
            children: feature.tags.take(2).map((t) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: a.withOpacity(0.09), borderRadius: BorderRadius.circular(4)),
              child: Text(t,
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: a)),
            )).toList(),
          ),
          const SizedBox(height: 10),
          // Open button
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: a.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('Buka',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: a)),
              const SizedBox(width: 4),
              Icon(Icons.arrow_forward_rounded, size: 12, color: a),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ── Settings bottom sheet ─────────────────────────────────────────────────────
class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet();
  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late final TextEditingController _urlCtrl;
  final _api = ApiService();

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: _api.backendUrl);
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1A1E30) : Colors.white;
    final surface = isDark ? const Color(0xFF1E2640) : const Color(0xFFF5F6FA);
    final border = isDark ? const Color(0xFF2A3050) : const Color(0xFFE4E7F0);
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final textSub = isDark ? const Color(0xFF8892B0) : const Color(0xFF9B9FAD);
    final label = isDark ? const Color(0xFF6B7394) : const Color(0xFF9B9FAD);

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            width: 40, height: 4,
            decoration: BoxDecoration(
                color: border, borderRadius: BorderRadius.circular(2)),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Row(children: [
              const Icon(Icons.tune_rounded, color: Color(0xFF7B8BFF), size: 22),
              const SizedBox(width: 10),
              Text('Pengaturan',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold, color: textPrimary)),
            ]),
          ),
          Divider(color: border, height: 1),

          // ── Section: Tampilan ──────────────────────────────────────────────
          _sectionLabel('TAMPILAN', label),
          const SizedBox(height: 4),

          // Dark mode toggle
          ValueListenableBuilder<ThemeMode>(
            valueListenable: AppSettings.themeMode,
            builder: (ctx, mode, _) {
              final dark = mode == ThemeMode.dark;
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                leading: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Icon(
                    dark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                    key: ValueKey(dark),
                    color: dark ? const Color(0xFF7B8BFF) : const Color(0xFFFFB74D),
                    size: 24,
                  ),
                ),
                title: Text(
                  dark ? 'Mode Gelap' : 'Mode Terang',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600, color: textPrimary),
                ),
                subtitle: Text(
                  dark ? 'Cocok untuk malam hari' : 'Cocok untuk siang hari',
                  style: TextStyle(fontSize: 12, color: textSub),
                ),
                trailing: Switch.adaptive(
                  value: dark,
                  activeColor: const Color(0xFF7B8BFF),
                  onChanged: AppSettings.setDarkMode,
                ),
              );
            },
          ),

          // View mode
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Tampilan Beranda',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600, color: textPrimary)),
              const SizedBox(height: 2),
              Text('Pilih cara menampilkan fitur',
                  style: TextStyle(fontSize: 12, color: textSub)),
              const SizedBox(height: 10),
              ValueListenableBuilder<String>(
                valueListenable: AppSettings.viewMode,
                builder: (ctx, view, _) => Container(
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: border),
                  ),
                  padding: const EdgeInsets.all(4),
                  child: Row(children: [
                    _viewBtn('list', Icons.view_agenda_rounded, 'List', view == 'list'),
                    _viewBtn('grid', Icons.grid_view_rounded, 'Grid', view == 'grid'),
                  ]),
                ),
              ),
            ]),
          ),

          Divider(color: border, height: 1),

          // ── Section: Koneksi ───────────────────────────────────────────────
          _sectionLabel('KONEKSI', label),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.cloud_outlined, size: 16, color: textSub),
                const SizedBox(width: 6),
                Text('URL Backend Server',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600, color: textPrimary)),
              ]),
              const SizedBox(height: 2),
              Text('Untuk fitur Video Downloader',
                  style: TextStyle(fontSize: 12, color: textSub)),
              const SizedBox(height: 10),
              TextField(
                controller: _urlCtrl,
                style: TextStyle(fontSize: 14, color: textPrimary),
                decoration: const InputDecoration(
                  hintText: 'http://192.168.1.x:8000',
                  prefixIcon: Icon(Icons.link_rounded, size: 18),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '• Emulator: http://10.0.2.2:8000\n'
                '• HP Fisik: http://<IP-Komputer>:8000',
                style: TextStyle(fontSize: 11, color: label, height: 1.6),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.save_rounded, size: 18),
                  label: const Text('Simpan URL'),
                  onPressed: () async {
                    await _api.setBackendUrl(_urlCtrl.text.trim());
                    if (!context.mounted) return;
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: const Text('Backend URL disimpan'),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ));
                  },
                  style: ElevatedButton.styleFrom(minimumSize: const Size(0, 48)),
                ),
              ),
            ]),
          ),

          SafeArea(
            top: false,
            child: const SizedBox(height: 20),
          ),
        ]),
      ),
    );
  }

  Widget _sectionLabel(String text, Color color) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        child: Text(text,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
                letterSpacing: 1)),
      );

  Widget _viewBtn(String mode, IconData icon, String label, bool selected) {
    const accent = Color(0xFF7B8BFF);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final unselColor = isDark ? const Color(0xFF6B7394) : const Color(0xFF9B9FAD);
    return Expanded(
      child: GestureDetector(
        onTap: () => AppSettings.setViewMode(mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? accent.withOpacity(0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border: selected ? Border.all(color: accent.withOpacity(0.5)) : null,
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 16, color: selected ? accent : unselColor),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    color: selected ? accent : unselColor)),
          ]),
        ),
      ),
    );
  }
}
