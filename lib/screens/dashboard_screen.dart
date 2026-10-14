import 'dart:io';

import 'package:flutter/material.dart';
import '../models/recent_file.dart';
import '../services/api_service.dart';
import '../services/app_settings.dart';
import '../services/history_service.dart';
import '../services/update_service.dart';
import '../utils/app_theme.dart';
import 'home_screen.dart';
import 'pdf_viewer_screen.dart';
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
    required this.icon,
    required this.title,
    required this.description,
    required this.accentColor,
    required this.tags,
    required this.onTap,
  });
}

// ── Dashboard ─────────────────────────────────────────────────────────────────
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<_RecentItem> _recent = [];

  @override
  void initState() {
    super.initState();
    _loadRecent();
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
              'Download videos from YouTube, TikTok, Instagram, Facebook, and 1000+ other platforms',
          accentColor: AppTheme.downloaderColor,
          tags: const ['YouTube', 'TikTok', 'Instagram', '+1000'],
          onTap: () => _push(const HomeScreen()),
        ),
        _Feature(
          icon: Icons.menu_book_rounded,
          title: 'Document Reader',
          description:
              'Open PDF, Word, Excel, PowerPoint and TXT files right in the app',
          accentColor: AppTheme.readerColor,
          tags: const ['PDF', 'Word', 'Excel', 'PPT'],
          onTap: () => _push(const ReaderScreen()),
        ),
        _Feature(
          icon: Icons.document_scanner_rounded,
          title: 'Document Scanner',
          description:
              'Scan ID cards, diplomas, licenses, certificates and more. Save as PDF or JPG',
          accentColor: AppTheme.scannerColor,
          tags: const ['ID Card', 'Diploma', 'License', 'Certificate'],
          onTap: () => _push(const ScannerScreen()),
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
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(children: [
              const Icon(Icons.system_update, color: Color(0xFF7B8BFF)),
              const SizedBox(width: 8),
              Text('Update Available',
                  style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                      fontSize: 17)),
            ]),
            content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Version ${update.version} is available.',
                      style: TextStyle(
                          color: isDark
                              ? Colors.white70
                              : const Color(0xFF555770))),
                  if (update.releaseNotes.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(update.releaseNotes,
                        style: TextStyle(
                            color: isDark
                                ? Colors.white38
                                : const Color(0xFF9B9FAD),
                            fontSize: 12),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis),
                  ],
                  if (downloading) ...[
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      value: progress,
                      backgroundColor:
                          isDark ? Colors.white12 : const Color(0xFFE4E7F0),
                      color: const Color(0xFF7B8BFF),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    const SizedBox(height: 4),
                    Text('${(progress * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                            color: isDark
                                ? Colors.white54
                                : const Color(0xFF9B9FAD),
                            fontSize: 12)),
                  ],
                ]),
            actions: downloading
                ? []
                : [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text('Later',
                          style: TextStyle(
                              color: isDark
                                  ? Colors.white38
                                  : const Color(0xFF9B9FAD))),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7B8BFF),
                          foregroundColor: Colors.white,
                          minimumSize: Size.zero,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 10)),
                      onPressed: () async {
                        set(() => downloading = true);
                        await UpdateService.downloadAndInstall(
                          update.downloadUrl,
                          (p) => set(() => progress = p),
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      child: const Text('Update Now'),
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
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: const _SettingsSheet(),
      ),
    );
  }

  // ── Recent documents ────────────────────────────────────────────────────────
  Future<void> _loadRecent() async {
    final items = <_RecentItem>[];
    for (final f in await HistoryService.loadRecentFiles()) {
      if (items.length >= 5) break;
      if (!await File(f.path).exists()) continue;
      final page = f.extension == 'pdf'
          ? await PdfViewerScreen.lastReadPage(f.path)
          : null;
      items.add(_RecentItem(f, page));
    }
    if (mounted) setState(() => _recent = items);
  }

  Future<void> _openRecent(RecentFile f) async {
    await HistoryService.touchRecentFile(f.path, f.name, f.extension);
    if (!mounted) return;
    final ok = await openDocumentViewer(context, f.path, f.name, f.extension);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('.${f.extension.toUpperCase()} format is not supported')));
    }
    _loadRecent();
  }

  Future<void> _push(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    _loadRecent();
  }

  // ── Build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final features = _features();
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadRecent,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _buildHeader(context),
              const SizedBox(height: 24),
              ValueListenableBuilder<String>(
                valueListenable: AppSettings.viewMode,
                builder: (ctx, view, _) => view == 'grid'
                    ? _BentoGrid(features: features)
                    : Column(
                        children: features
                            .expand((f) => [
                                  _FeatureListCard(feature: f),
                                  const SizedBox(height: 12),
                                ])
                            .toList(),
                      ),
              ),
              const SizedBox(height: 32),
              _buildRecentSection(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final sub = theme.colorScheme.onSurfaceVariant;
    final hour = DateTime.now().hour;
    final greet = hour < 11
        ? 'Good morning'
        : hour < 15
            ? 'Good afternoon'
            : hour < 19
                ? 'Good evening'
                : 'Good night';

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(children: [
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$greet 👋', style: TextStyle(fontSize: 14, color: sub)),
            const SizedBox(height: 4),
            Text('SuperApp HD', style: theme.textTheme.headlineSmall),
          ]),
        ),
        SoftCard(
          padding: const EdgeInsets.all(12),
          onTap: _openSettings,
          child: Icon(Icons.tune_rounded,
              size: 22, color: theme.colorScheme.onSurface),
        ),
      ]),
    );
  }

  Widget _buildRecentSection(BuildContext context) {
    final theme = Theme.of(context);
    final sub = theme.colorScheme.onSurfaceVariant;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('Recently opened', style: theme.textTheme.titleMedium),
        const Spacer(),
        if (_recent.isNotEmpty)
          TextButton(
            onPressed: () => _push(const ReaderScreen()),
            child: const Text('See all'),
          ),
      ]),
      const SizedBox(height: 8),
      if (_recent.isEmpty)
        SoftCard(
          padding: const EdgeInsets.all(20),
          child: Row(children: [
            Icon(Icons.history_rounded, color: sub),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Documents you open will appear here',
                  style: TextStyle(fontSize: 13, color: sub)),
            ),
          ]),
        )
      else
        ..._recent.expand((r) => [
              _RecentTile(item: r, onTap: () => _openRecent(r.file)),
              const SizedBox(height: 8),
            ]),
    ]);
  }
}

// ── Bento grid ────────────────────────────────────────────────────────────────
// Kartu besar (Downloader) di kiri, dua kartu kecil bertumpuk di kanan.
class _BentoGrid extends StatelessWidget {
  final List<_Feature> features;
  const _BentoGrid({required this.features});

  @override
  Widget build(BuildContext context) {
    final main = features.first;
    final rest = features.skip(1).toList();
    return SizedBox(
      height: 280,
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: _HeroCard(feature: main)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(children: [
            for (var i = 0; i < rest.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              Expanded(child: _SmallCard(feature: rest[i])),
            ],
          ]),
        ),
      ]),
    );
  }
}

class _HeroCard extends StatelessWidget {
  final _Feature feature;
  const _HeroCard({required this.feature});

  @override
  Widget build(BuildContext context) {
    final a = feature.accentColor;
    return SoftCard(
      onTap: feature.onTap,
      padding: const EdgeInsets.all(20),
      shadowTint: a,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [a, Color.lerp(a, Colors.black, 0.18)!],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(AppTheme.radiusButton),
          ),
          child: Icon(feature.icon, color: Colors.white, size: 28),
        ),
        const Spacer(),
        Text(feature.title,
            style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                height: 1.15)),
        const SizedBox(height: 6),
        Text(feature.tags.join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style:
                TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.85))),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppTheme.radiusButton),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.content_paste_rounded, size: 16, color: a),
            const SizedBox(width: 6),
            Text('Paste link',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, color: a)),
          ]),
        ),
      ]),
    );
  }
}

class _SmallCard extends StatelessWidget {
  final _Feature feature;
  const _SmallCard({required this.feature});

  @override
  Widget build(BuildContext context) {
    final a = feature.accentColor;
    final sub = Theme.of(context).colorScheme.onSurfaceVariant;
    return SoftCard(
      onTap: feature.onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: a.withOpacity(0.14),
              borderRadius: BorderRadius.circular(AppTheme.radiusChip),
            ),
            child: Icon(feature.icon, color: a, size: 22),
          ),
          const Spacer(),
          Icon(Icons.arrow_outward_rounded, size: 18, color: sub),
        ]),
        const Spacer(),
        Text(feature.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(feature.tags.take(3).join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: sub)),
      ]),
    );
  }
}

// ── Feature card (list view) ──────────────────────────────────────────────────
class _FeatureListCard extends StatelessWidget {
  final _Feature feature;
  const _FeatureListCard({required this.feature});

  @override
  Widget build(BuildContext context) {
    final a = feature.accentColor;
    final sub = Theme.of(context).colorScheme.onSurfaceVariant;
    return SoftCard(
      onTap: feature.onTap,
      padding: const EdgeInsets.all(20),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: a.withOpacity(0.14),
            borderRadius: BorderRadius.circular(AppTheme.radiusButton),
          ),
          child: Icon(feature.icon, color: a, size: 26),
        ),
        const SizedBox(width: 16),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(feature.title,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(feature.description,
                style: TextStyle(fontSize: 13, color: sub, height: 1.4)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: feature.tags
                  .map((t) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: a.withOpacity(0.1),
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusChip),
                        ),
                        child: Text(t,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: a)),
                      ))
                  .toList(),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ── Recent document tile ──────────────────────────────────────────────────────
class _RecentItem {
  final RecentFile file;
  final int? pdfPage; // 0-based, halaman terakhir dibaca
  const _RecentItem(this.file, this.pdfPage);
}

class _RecentTile extends StatelessWidget {
  final _RecentItem item;
  final VoidCallback onTap;
  const _RecentTile({required this.item, required this.onTap});

  static (IconData, Color) _style(String ext) => switch (ext) {
        'pdf' => (Icons.picture_as_pdf_rounded, const Color(0xFFE53935)),
        'docx' || 'odt' => (Icons.article_rounded, const Color(0xFF1565C0)),
        'xlsx' || 'ods' => (Icons.table_chart_rounded, const Color(0xFF217346)),
        'pptx' || 'odp' => (Icons.slideshow_rounded, const Color(0xFFD24726)),
        'csv' => (Icons.grid_on_rounded, const Color(0xFF00695C)),
        _ => (Icons.text_snippet_rounded, const Color(0xFF546E7A)),
      };

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _style(item.file.extension);
    final sub = Theme.of(context).colorScheme.onSurfaceVariant;
    final page = item.pdfPage;

    return SoftCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(AppTheme.radiusChip),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.file.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(timeAgo(item.file.date),
                style: TextStyle(fontSize: 12, color: sub)),
          ]),
        ),
        if (page != null && page > 0)
          Container(
            margin: const EdgeInsets.only(left: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppTheme.readerColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(AppTheme.radiusChip),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.bookmark_rounded,
                  size: 13, color: AppTheme.readerColor),
              const SizedBox(width: 4),
              Text('Page ${page + 1}',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.readerColor)),
            ]),
          )
        else
          Icon(Icons.chevron_right_rounded, color: sub),
      ]),
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
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: border, borderRadius: BorderRadius.circular(2)),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Row(children: [
              const Icon(Icons.tune_rounded,
                  color: Color(0xFF7B8BFF), size: 22),
              const SizedBox(width: 10),
              Text('Settings',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: textPrimary)),
            ]),
          ),
          Divider(color: border, height: 1),

          // ── Section: Tampilan ──────────────────────────────────────────────
          _sectionLabel('APPEARANCE', label),
          const SizedBox(height: 4),

          // Dark mode toggle
          ValueListenableBuilder<ThemeMode>(
            valueListenable: AppSettings.themeMode,
            builder: (ctx, mode, _) {
              final dark = mode == ThemeMode.dark;
              return ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                leading: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Icon(
                    dark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                    key: ValueKey(dark),
                    color: dark
                        ? const Color(0xFF7B8BFF)
                        : const Color(0xFFFFB74D),
                    size: 24,
                  ),
                ),
                title: Text(
                  dark ? 'Dark Mode' : 'Light Mode',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: textPrimary),
                ),
                subtitle: Text(
                  dark ? 'Easier on the eyes at night' : 'Best for daytime use',
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
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Home Layout',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: textPrimary)),
              const SizedBox(height: 2),
              Text('Choose how features are displayed',
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
                    _viewBtn('grid', Icons.dashboard_rounded, 'Bento',
                        view == 'grid'),
                    _viewBtn('list', Icons.view_agenda_rounded, 'List',
                        view == 'list'),
                  ]),
                ),
              ),
            ]),
          ),

          Divider(color: border, height: 1),

          // ── Section: History ───────────────────────────────────────────────
          _sectionLabel('HISTORY', label),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Text('Maximum number of items kept in each history (1–100)',
                style: TextStyle(fontSize: 12, color: textSub)),
          ),
          _historyLimitTile(
              Icons.download_rounded,
              'Video Downloader',
              AppTheme.downloaderColor,
              HistoryService.downloaderLimit,
              textPrimary),
          _historyLimitTile(Icons.menu_book_rounded, 'Document Reader',
              AppTheme.readerColor, HistoryService.readerLimit, textPrimary),
          _historyLimitTile(Icons.document_scanner_rounded, 'Document Scanner',
              AppTheme.scannerColor, HistoryService.scannerLimit, textPrimary),
          const SizedBox(height: 8),

          Divider(color: border, height: 1),

          // ── Section: Koneksi ───────────────────────────────────────────────
          _sectionLabel('CONNECTION', label),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.cloud_outlined, size: 16, color: textSub),
                const SizedBox(width: 6),
                Text('Backend Server URL',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: textPrimary)),
              ]),
              const SizedBox(height: 2),
              Text('Used by the Video Downloader',
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
                '• Physical phone: http://<Computer-IP>:8000',
                style: TextStyle(fontSize: 11, color: label, height: 1.6),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.save_rounded, size: 18),
                  label: const Text('Save URL'),
                  onPressed: () async {
                    await _api.setBackendUrl(_urlCtrl.text.trim());
                    if (!context.mounted) return;
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: const Text('Backend URL saved'),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ));
                  },
                  style:
                      ElevatedButton.styleFrom(minimumSize: const Size(0, 48)),
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

  Widget _historyLimitTile(IconData icon, String title, Color color,
      ValueNotifier<int> limit, Color textPrimary) {
    return ValueListenableBuilder<int>(
      valueListenable: limit,
      builder: (ctx, value, _) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
        child: Row(children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          SizedBox(
            width: 120,
            child: Text(title,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: textPrimary)),
          ),
          Expanded(
            child: Slider(
              value: value.toDouble(),
              min: HistoryService.minLimit.toDouble(),
              max: HistoryService.maxLimit.toDouble(),
              divisions: HistoryService.maxLimit - HistoryService.minLimit,
              activeColor: color,
              label: '$value',
              // Update tampilan saat digeser, simpan saat dilepas
              onChanged: (v) => limit.value = v.round(),
              onChangeEnd: (v) => HistoryService.setLimit(limit, v.round()),
            ),
          ),
          SizedBox(
            width: 32,
            child: Text('$value',
                textAlign: TextAlign.end,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: textPrimary)),
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
    final unselColor =
        isDark ? const Color(0xFF6B7394) : const Color(0xFF9B9FAD);
    return Expanded(
      child: GestureDetector(
        onTap: () => AppSettings.setViewMode(mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? accent.withOpacity(0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border:
                selected ? Border.all(color: accent.withOpacity(0.5)) : null,
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

