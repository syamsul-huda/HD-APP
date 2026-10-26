import 'dart:ui' show Color;
import 'doc_model.dart';
import 'doc_render.dart';

/// Bagi dokumen menjadi halaman seperti Word.
///
/// Jika dokumen disimpan Word (`hasRenderedBreaks`), posisi pindah halaman
/// hasil render Word dipakai apa adanya → halaman identik. Jika tidak,
/// tinggi blok diukur ([DocRenderer.measure], skala 1 pt) dengan font yang
/// metriknya sama dengan Office, paragraf panjang dipecah per baris, dan
/// tabel dipecah per baris tabel dengan header yang diulang.
///
/// Ukuran dihitung dalam unit renderer ([DocRenderer.scale] unit per point).
/// Label footnote yang dirujuk di dalam blok (termasuk di sel tabel).
Iterable<String> footnoteLabels(DocBlock b) sync* {
  if (b is DocParagraph) {
    for (final i in b.inlines) {
      if (i is DocText && i.footnote != null) yield i.footnote!;
    }
  } else if (b is DocTable) {
    for (final r in b.rows) {
      for (final c in r.cells) {
        for (final x in c.blocks) {
          yield* footnoteLabels(x);
        }
      }
    }
  }
}

DocParagraph _sectionTitle(String title) => DocParagraph(
      inlines: [DocText(title, bold: true, fontSize: 12, color: const Color(0xFF1F3864))],
      spaceBefore: 18,
      spaceAfter: 6,
      keepNext: true,
    );

/// Isi di luar badan dokumen yang tetap harus terlihat: endnote, komentar,
/// dan (untuk tampilan mobile) footnote serta header/footer.
List<DocBlock> documentAppendix(DocDocument doc, {required bool mobile}) {
  final out = <DocBlock>[];
  if (mobile && doc.footnotes.isNotEmpty) {
    out.add(_sectionTitle('Footnotes'));
    for (final blocks in doc.footnotes.values) {
      out.addAll(blocks);
    }
  }
  if (doc.endnotes.isNotEmpty) {
    out.add(_sectionTitle('Endnotes'));
    for (final n in doc.endnotes) {
      out.addAll(n.blocks);
    }
  }
  if (doc.comments.isNotEmpty) {
    out.add(_sectionTitle('Comments'));
    for (final n in doc.comments) {
      out.add(DocParagraph(inlines: [
        DocText('${n.label}  ', bold: true, color: const Color(0xFFC0504D)),
        DocText(n.author ?? '', bold: true),
      ], spaceBefore: 6, keepNext: true));
      out.addAll(n.blocks);
    }
  }
  bool hasText(List<DocBlock> bs) =>
      bs.any((b) => b is DocTable || (b is DocParagraph && b.plainText.trim().isNotEmpty));
  if (mobile) {
    for (final (title, blocks) in [
      ('Header', doc.header),
      ('Footer', doc.footer),
      if (doc.firstHeader != null) ('First page header', doc.firstHeader!),
      if (doc.firstFooter != null) ('First page footer', doc.firstFooter!),
    ]) {
      if (!hasText(blocks)) continue;
      out.add(_sectionTitle(title));
      out.addAll(blocks);
    }
  }
  return out;
}

/// Word memakai jarak terbesar antara "spasi sesudah" paragraf sebelumnya dan
/// "spasi sebelum" paragraf berikutnya (bukan jumlahnya). Spasi sebelum
/// dikurangi agar penjumlahan di layout menghasilkan nilai maksimum itu.
List<DocBlock> collapseParagraphSpacing(List<DocBlock> blocks) {
  final out = <DocBlock>[];
  DocParagraph? prev;
  for (final b in blocks) {
    if (b is DocParagraph) {
      final adjusted = prev != null && b.spaceBefore > 0
          ? b.withSpaceBefore((b.spaceBefore - prev.spaceAfter).clamp(0.0, b.spaceBefore))
          : b;
      out.add(adjusted);
      prev = b;
    } else if (b is DocTable) {
      out.add(b.withRows([
        for (final row in b.rows)
          DocTableRow([
            for (final c in row.cells)
              DocTableCell(collapseParagraphSpacing(c.blocks),
                  colSpan: c.colSpan, shading: c.shading, mergedContinue: c.mergedContinue)
          ], header: row.header)
      ]));
      prev = null;
    } else {
      out.add(b);
      // Pindah halaman: paragraf berikutnya mulai di halaman baru
      prev = null;
    }
  }
  return out;
}

List<List<DocBlock>> paginateDocument(DocDocument doc, DocRenderer r) {
  final pages = <List<DocBlock>>[];
  for (final p in paginateIncrementally(doc, r)) {
    pages.add(p);
  }
  return pages.isEmpty ? [[]] : pages;
}

/// Versi bertahap: menghasilkan halaman satu per satu sehingga tampilan bisa
/// menampilkan halaman awal lebih dulu dan menghitung sisanya di sela frame.
Iterable<List<DocBlock>> paginateIncrementally(DocDocument doc, DocRenderer r) sync* {
  final w = doc.textWidth * r.scale;
  final h = (doc.page.height - doc.page.marginTop - doc.page.marginBottom) * r.scale;
  final pages = <List<DocBlock>>[[]];
  var y = 0.0;
  var emitted = 0;
  var pageNotes = <String>{}; // footnote yang sudah ada di halaman ini
  var notesH = 0.0;
  void newPage() {
    if (pages.last.isEmpty) return;
    pages.add([]);
    y = 0;
    pageNotes = {};
    notesH = 0;
  }

  final body = [...doc.blocks, ...documentAppendix(doc, mobile: false)];
  final queue = r.exact ? collapseParagraphSpacing(body) : body;

  // Footnote di dasar halaman: tingginya dikurangkan dari ruang halaman
  final noteSep = 12.0 * r.scale;
  final noteHeights = <String, double>{};
  double noteH(String label) => noteHeights[label] ??=
      (doc.footnotes[label] ?? const <DocBlock>[]).fold<double>(0, (a, b) => a + r.measure(b, w));
  double extraNotes(DocBlock b) {
    final fresh = footnoteLabels(b).where((l) => !pageNotes.contains(l)).toSet();
    if (fresh.isEmpty) return 0;
    return fresh.fold<double>(0, (a, l) => a + noteH(l)) + (pageNotes.isEmpty ? noteSep : 0);
  }

  void place(DocBlock b, double bh) {
    final fresh = footnoteLabels(b).where((l) => !pageNotes.contains(l)).toSet();
    if (fresh.isNotEmpty) {
      notesH += fresh.fold<double>(0, (a, l) => a + noteH(l)) + (pageNotes.isEmpty ? noteSep : 0);
      pageNotes.addAll(fresh);
    }
    pages.last.add(b);
    y += bh;
  }

  var i = 0;
  while (i < queue.length) {
    // Halaman yang sudah ditutup (bukan halaman terakhir) bisa diserahkan
    while (emitted < pages.length - 1) {
      yield pages[emitted++];
    }
    final b = queue[i++];
    if (b is DocPageBreak) {
      if (!b.soft || doc.hasRenderedBreaks) newPage();
      continue;
    }
    if (b is DocParagraph && b.pageBreakBefore) newPage();
    if (doc.hasRenderedBreaks) {
      pages.last.add(b);
      continue;
    }

    final bh = r.measure(b, w);
    // Ruang halaman = tinggi area teks − footnote yang sudah/akan ada di halaman ini
    final room = h - notesH - extraNotes(b);
    // "Keep with next": paragraf ini harus satu halaman dengan awal paragraf
    // berikutnya (minimal 2 baris pertamanya), seperti judul di Word
    if (b is DocParagraph && b.keepNext && i < queue.length && pages.last.isNotEmpty) {
      final next = queue[i];
      final nextH = next is DocPageBreak ? 0.0 : r.minStartHeight(next, w);
      if (y + bh + nextH > room && y + bh <= room) {
        newPage();
      }
    }
    // Spasi sesudah paragraf boleh terpotong di dasar halaman (seperti Word)
    final trailing = switch (b) {
      DocParagraph() => b.spaceAfter * r.scale + r.lineSlack(b),
      DocTable() when b.rows.isNotEmpty => r.rowSlack(b.rows.last),
      _ => 0.0,
    };
    final space = h - notesH - extraNotes(b);
    if (y + bh - trailing <= space + 0.5) {
      place(b, bh);
      continue;
    }

    if (b is DocParagraph) {
      final parts = r.split(b, w, space - y);
      if (parts != null) {
        place(parts.$1, r.measure(parts.$1, w));
        newPage();
        queue.insert(i, parts.$2);
        continue;
      }
    } else if (b is DocTable && b.rows.length > 1) {
      final heights = r.rowHeights(b, w);
      final header = b.rows.takeWhile((row) => row.header).length;
      var acc = y + r.tableVerticalPadding * 2;
      var fit = 0;
      while (fit < heights.length && acc + heights[fit] - r.rowSlack(b.rows[fit]) <= space) {
        acc += heights[fit];
        fit++;
      }
      // Baris berikutnya boleh terpotong: sisakan bagian yang muat di sini
      if (fit < b.rows.length && fit >= header) {
        final parts = r.splitRow(b, b.rows[fit], w, space - acc, firstRow: fit == 0);
        if (parts != null) {
          final top = b.withRows([...b.rows.sublist(0, fit), parts.$1]);
          place(top, r.measure(top, w));
          newPage();
          queue.insert(i, b.withRows([...b.rows.take(header), parts.$2, ...b.rows.sublist(fit + 1)]));
          continue;
        }
      }
      if (fit > header && fit < b.rows.length) {
        final top = b.withRows(b.rows.sublist(0, fit));
        place(top, r.measure(top, w));
        newPage();
        queue.insert(i, b.withRows([...b.rows.take(header), ...b.rows.sublist(fit)]));
        continue;
      }
    }

    if (pages.last.isEmpty) {
      // Lebih tinggi dari satu halaman dan tidak bisa dipecah: biarkan meluber
      place(b, bh);
    } else {
      newPage();
      queue.insert(i, b);
    }
  }
  if (pages.length > 1 && pages.last.isEmpty) pages.removeLast();
  while (emitted < pages.length) {
    yield pages[emitted++];
  }
}
