import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/painting.dart';
import 'package:xml/xml.dart';

/// Paket Office (DOCX/XLSX/PPTX/ODT/ODS/ODP) = file zip berisi XML.
class OfficePackage {
  final Map<String, ArchiveFile> _files = {};

  OfficePackage(Uint8List bytes) {
    for (final f in ZipDecoder().decodeBytes(bytes)) {
      if (f.isFile) _files[f.name] = f;
    }
  }

  bool has(String path) => _files.containsKey(path);

  Iterable<String> get names => _files.keys;

  Uint8List? bytes(String path) {
    final f = _files[path];
    if (f == null) return null;
    final c = f.content;
    return c is Uint8List ? c : Uint8List.fromList(c as List<int>);
  }

  String? text(String path) {
    final b = bytes(path);
    return b == null ? null : utf8.decode(b, allowMalformed: true);
  }

  XmlDocument? xml(String path) {
    final t = text(path);
    return t == null ? null : XmlDocument.parse(t);
  }

  /// Relasi OOXML: id → path absolut di dalam zip.
  /// `ppt/slides/slide1.xml` → `ppt/slides/_rels/slide1.xml.rels`.
  Map<String, String> rels(String partPath) {
    final slash = partPath.lastIndexOf('/');
    final dir = slash < 0 ? '' : partPath.substring(0, slash);
    final file = partPath.substring(slash + 1);
    final doc = xml('${dir.isEmpty ? '' : '$dir/'}_rels/$file.rels');
    final out = <String, String>{};
    if (doc == null) return out;
    for (final r in doc.descendantElements.where((e) => e.localName == 'Relationship')) {
      final id = r.getAttribute('Id');
      final target = r.getAttribute('Target');
      if (id == null || target == null) continue;
      if (r.getAttribute('TargetMode') == 'External') continue;
      out[id] = resolvePath(dir, target);
    }
    return out;
  }

  /// Gabungkan direktori + target relatif (mendukung `../` dan `/`).
  static String resolvePath(String dir, String target) {
    if (target.startsWith('/')) return target.substring(1);
    final parts = dir.isEmpty ? <String>[] : dir.split('/');
    for (final seg in target.split('/')) {
      if (seg == '..') {
        if (parts.isNotEmpty) parts.removeLast();
      } else if (seg != '.' && seg.isNotEmpty) {
        parts.add(seg);
      }
    }
    return parts.join('/');
  }
}

// ── Teks polos (TXT / CSV) ────────────────────────────────────────────────────

/// Decode teks dengan deteksi encoding: BOM UTF-8/UTF-16, lalu UTF-8 ketat;
/// jika bukan UTF-8 valid (mis. CSV hasil Excel Windows), pakai Windows-1252
/// agar huruf seperti é/ñ/“ ” tidak berubah menjadi �.
String decodeText(List<int> b) {
  if (b.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) {
    return utf8.decode(b.sublist(3), allowMalformed: true);
  }
  if (b.length >= 2 && (b[0] == 0xFF && b[1] == 0xFE || b[0] == 0xFE && b[1] == 0xFF)) {
    final le = b[0] == 0xFF;
    final units = <int>[];
    for (var i = 2; i + 1 < b.length; i += 2) {
      units.add(le ? b[i] | (b[i + 1] << 8) : (b[i] << 8) | b[i + 1]);
    }
    return String.fromCharCodes(units);
  }
  try {
    return utf8.decode(b);
  } on FormatException {
    return String.fromCharCodes(b.map((c) => c >= 0x80 && c <= 0x9F ? _cp1252[c - 0x80] : c));
  }
}

// Windows-1252 0x80–0x9F (sisanya identik dengan Latin-1)
const _cp1252 = [
  0x20AC, 0x81, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, //
  0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x8D, 0x017D, 0x8F,
  0x90, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
  0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x9D, 0x017E, 0x0178,
];

// ── XML helpers ───────────────────────────────────────────────────────────────

extension XmlX on XmlElement {
  XmlElement? child(String local) {
    for (final e in childElements) {
      if (e.localName == local) return e;
    }
    return null;
  }

  Iterable<XmlElement> kids(String local) =>
      childElements.where((e) => e.localName == local);

  XmlElement? descendant(String local) {
    for (final e in descendantElements) {
      if (e.localName == local) return e;
    }
    return null;
  }

  /// Atribut berdasarkan nama lokal, abaikan prefix namespace
  /// (`w:val`, `val`, `a:val` semuanya cocok dengan `val`).
  String? attr(String local) {
    for (final a in attributes) {
      if (a.name.local == local) return a.value;
    }
    return null;
  }

  /// Atribut dengan prefix tertentu, mis. `attrNs('fo', 'font-size')`.
  String? attrNs(String prefix, String local) {
    for (final a in attributes) {
      if (a.name.local == local && a.name.prefix == prefix) return a.value;
    }
    return null;
  }

  /// OOXML boolean toggle: `<w:b/>`, `<w:b w:val="0"/>`, `<w:b w:val="false"/>`.
  bool? toggle(String local) {
    final e = child(local);
    if (e == null) return null;
    final v = e.attr('val');
    return !(v == '0' || v == 'false' || v == 'off' || v == 'none');
  }
}

extension XmlDocX on XmlDocument {
  XmlElement? first(String local) {
    for (final e in descendantElements) {
      if (e.localName == local) return e;
    }
    return null;
  }
}

// ── Warna ─────────────────────────────────────────────────────────────────────

Color? parseHexColor(String? hex) {
  if (hex == null) return null;
  var h = hex.trim().replaceFirst('#', '');
  if (h.length == 8) h = h.substring(2); // ARGB → RGB (alpha Excel jarang dipakai)
  if (h.length != 6) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

/// HSL yang aman untuk warna abu-abu: `HSLColor.fromColor` Flutter memberi
/// saturasi 1.0 untuk hitam, sehingga "hitam + terang 50%" menjadi merah.
HSLColor safeHsl(Color c) {
  final h = HSLColor.fromColor(c);
  final gray = c.red == c.green && c.green == c.blue;
  if (gray || h.saturation.isNaN || h.hue.isNaN) {
    return HSLColor.fromAHSL(h.alpha, 0, 0, c.red / 255);
  }
  return h;
}

/// Konversi warna ke HSL dan ubah luminance (lumMod/lumOff OOXML).
Color modLuminance(Color c, {double mod = 1, double off = 0}) {
  final hsl = safeHsl(c);
  final l = (hsl.lightness * mod + off).clamp(0.0, 1.0);
  return hsl.withLightness(l).toColor();
}

/// Tint Excel: positif = lebih terang, negatif = lebih gelap.
Color applyTint(Color c, double tint) {
  if (tint == 0) return c;
  final hsl = safeHsl(c);
  final l = hsl.lightness;
  final nl = tint < 0 ? l * (1 + tint) : l * (1 - tint) + tint;
  return hsl.withLightness(nl.clamp(0.0, 1.0)).toColor();
}

/// Terapkan modifier warna DrawingML (child dari srgbClr/schemeClr).
Color applyColorMods(Color c, XmlElement clr) {
  var out = c;
  double? lumMod, lumOff;
  for (final m in clr.childElements) {
    final v = (int.tryParse(m.attr('val') ?? '') ?? 0) / 100000.0;
    switch (m.localName) {
      case 'lumMod':
        lumMod = v;
      case 'lumOff':
        lumOff = v;
      case 'tint':
        // tint DrawingML: campur ke putih
        out = Color.lerp(kWhite, out, v)!;
      case 'shade':
        out = Color.lerp(kBlack, out, v)!;
      case 'alpha':
        out = out.withOpacity(v.clamp(0.0, 1.0));
    }
  }
  if (lumMod != null || lumOff != null) {
    out = modLuminance(out, mod: lumMod ?? 1, off: lumOff ?? 0);
  }
  return out;
}

const kWhite = Color(0xFFFFFFFF);
const kBlack = Color(0xFF000000);

/// Warna sistem `<a:sysClr val="windowText" lastClr="000000"/>`.
Color? sysColor(XmlElement e) => parseHexColor(e.attr('lastClr')) ??
    (e.attr('val') == 'window' ? kWhite : kBlack);

// ── Satuan ────────────────────────────────────────────────────────────────────

const double emuPerPt = 12700;

double emuToPt(String? v) => (double.tryParse(v ?? '') ?? 0) / emuPerPt;

double twipToPt(String? v) => (double.tryParse(v ?? '') ?? 0) / 20;

/// Panjang ODF: "2.5cm", "10mm", "1in", "12pt", "16px" → point.
double? odfLength(String? v) {
  if (v == null) return null;
  final m = RegExp(r'^(-?[\d.]+)\s*([a-z%]*)$').firstMatch(v.trim());
  if (m == null) return null;
  final n = double.tryParse(m.group(1)!);
  if (n == null) return null;
  switch (m.group(2)) {
    case 'cm':
      return n * 72 / 2.54;
    case 'mm':
      return n * 72 / 25.4;
    case 'in':
    case 'inch':
      return n * 72;
    case 'pc':
      return n * 12;
    case 'px':
      return n * 0.75;
    default:
      return n; // pt
  }
}

// ── Penomoran ────────────────────────────────────────────────────────────────

String toRoman(int n) {
  if (n <= 0) return '$n';
  const vals = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1];
  const syms = ['M', 'CM', 'D', 'CD', 'C', 'XC', 'L', 'XL', 'X', 'IX', 'V', 'IV', 'I'];
  final sb = StringBuffer();
  var x = n;
  for (var i = 0; i < vals.length; i++) {
    while (x >= vals[i]) {
      sb.write(syms[i]);
      x -= vals[i];
    }
  }
  return sb.toString();
}

String toLetters(int n) {
  if (n <= 0) return '$n';
  var x = n;
  final sb = StringBuffer();
  while (x > 0) {
    x--;
    sb.write(String.fromCharCode(97 + x % 26));
    x ~/= 26;
  }
  return sb.toString().split('').reversed.join();
}

/// Format nomor list sesuai jenisnya (decimal, lowerRoman, upperLetter, …).
String formatListNumber(String fmt, int n) {
  switch (fmt) {
    case 'lowerRoman':
    case 'i':
      return toRoman(n).toLowerCase();
    case 'upperRoman':
    case 'I':
      return toRoman(n);
    case 'lowerLetter':
    case 'a':
      return toLetters(n);
    case 'upperLetter':
    case 'A':
      return toLetters(n).toUpperCase();
    case 'decimalZero':
      return n.toString().padLeft(2, '0');
    default:
      return '$n';
  }
}

/// Simbol bullet yang aman ditampilkan (font Symbol/Wingdings tidak tersedia).
String bulletForLevel(int level) => const ['•', '◦', '▪'][level % 3];

// Karakter bullet populer di font simbol → padanan Unicode
const _wingdings = {
  0x6C: '●', 0x6E: '■', 0x71: '❑', 0x76: '❖', 0xA7: '▪', 0xD8: '➢', //
  0xFC: '✓', 0xE0: '➔', 0xE8: '➔', 0x77: '◆', 0x75: '◆',
};
const _wingdings3 = {0x75: '▸', 0x7D: '▸', 0x84: '▸', 0x50: '▸'};
const _symbol = {0xB7: '•', 0xA8: '♣', 0xAE: '→'};

/// Ganti karakter font simbol (Wingdings/Symbol, sering di area private-use
/// U+F0xx) dengan bullet Unicode yang bisa dirender font biasa.
String sanitizeBullet(String? s, int level, {String? font}) {
  if (s == null || s.trim().isEmpty) return bulletForLevel(level);
  var c = s.runes.first;
  if (c >= 0xF000 && c <= 0xF0FF) c -= 0xF000;
  final f = (font ?? '').toLowerCase();
  final mapped = f.contains('wingdings 3')
      ? _wingdings3[c]
      : f.contains('wingdings') || f.contains('webdings')
          ? _wingdings[c]
          : f.contains('symbol')
              ? _symbol[c]
              : null;
  if (mapped != null) return mapped;
  if (c >= 0xE000 && c <= 0xF8FF) return bulletForLevel(level);
  if (f.contains('wingdings') || f.contains('symbol') || f.contains('webdings')) {
    return bulletForLevel(level);
  }
  if (s.runes.first >= 0xF000 && s.runes.first <= 0xF0FF) return bulletForLevel(level);
  if (c == 0x6F || c == 0xA7) return bulletForLevel(level); // 'o' / '§' tanpa info font
  return s;
}

/// Format gambar yang bisa didekode Flutter (EMF/WMF/TIFF tidak).
bool isRenderableImage(String path) {
  final p = path.toLowerCase();
  return p.endsWith('.png') ||
      p.endsWith('.jpg') ||
      p.endsWith('.jpeg') ||
      p.endsWith('.gif') ||
      p.endsWith('.bmp') ||
      p.endsWith('.webp');
}

double clampD(double v, double lo, double hi) => math.max(lo, math.min(hi, v));
