/// Pemindai XML ringan untuk bagian besar dan berstruktur teratur
/// (sheetData & sharedStrings Excel). Puluhan kali lebih cepat daripada
/// membangun DOM untuk file berukuran megabyte.
class FastTag {
  final String name; // tanpa prefix namespace
  final int start; // posisi '<'
  final int end; // posisi setelah '>'
  final bool selfClosing;
  final bool closing;
  final String _src;
  final int _attrStart, _attrEnd;

  FastTag(this.name, this.start, this.end, this.selfClosing, this.closing, this._src,
      this._attrStart, this._attrEnd);

  /// Nilai atribut berdasarkan nama lokal (abaikan prefix), sudah di-unescape.
  String? attr(String local) {
    var i = _attrStart;
    while (i < _attrEnd) {
      while (i < _attrEnd && _isSpace(_src.codeUnitAt(i))) {
        i++;
      }
      final eq = _src.indexOf('=', i);
      if (eq < 0 || eq >= _attrEnd) return null;
      var n = _src.substring(i, eq).trim();
      final colon = n.indexOf(':');
      if (colon >= 0) n = n.substring(colon + 1);
      var q = eq + 1;
      while (q < _attrEnd && _isSpace(_src.codeUnitAt(q))) {
        q++;
      }
      final quote = _src[q];
      final close = _src.indexOf(quote, q + 1);
      if (close < 0) return null;
      if (n == local) return unescapeXml(_src.substring(q + 1, close));
      i = close + 1;
    }
    return null;
  }

  static bool _isSpace(int c) => c == 32 || c == 9 || c == 10 || c == 13;
}

/// Iterasi semua tag (buka/tutup/self-closing) dalam [s] mulai [from] s.d. [to].
Iterable<FastTag> scanTags(String s, [int from = 0, int? to]) sync* {
  final limit = to ?? s.length;
  var i = s.indexOf('<', from);
  while (i >= 0 && i < limit) {
    final c1 = i + 1 < s.length ? s.codeUnitAt(i + 1) : 0;
    if (c1 == 0x3F /* ? */ || c1 == 0x21 /* ! */) {
      // <?xml …?>, komentar, CDATA: lewati
      final end = s.startsWith('<!--', i)
          ? s.indexOf('-->', i) + 3
          : s.startsWith('<![CDATA[', i)
              ? s.indexOf(']]>', i) + 3
              : s.indexOf('>', i) + 1;
      if (end <= 0) return;
      i = s.indexOf('<', end);
      continue;
    }
    final closing = c1 == 0x2F; // '/'
    var p = closing ? i + 2 : i + 1;
    final nameStart = p;
    while (p < s.length) {
      final c = s.codeUnitAt(p);
      if (c == 0x3E || c == 0x2F || FastTag._isSpace(c)) break;
      p++;
    }
    var name = s.substring(nameStart, p);
    final colon = name.indexOf(':');
    if (colon >= 0) name = name.substring(colon + 1);
    // Cari '>' di luar tanda kutip
    var q = p;
    int? quote;
    while (q < s.length) {
      final c = s.codeUnitAt(q);
      if (quote != null) {
        if (c == quote) quote = null;
      } else if (c == 0x22 || c == 0x27) {
        quote = c;
      } else if (c == 0x3E) {
        break;
      }
      q++;
    }
    final selfClosing = q > 0 && s.codeUnitAt(q - 1) == 0x2F;
    yield FastTag(name, i, q + 1, selfClosing, closing, s, p, selfClosing ? q - 1 : q);
    i = s.indexOf('<', q + 1);
  }
}

/// Teks di antara tag pembuka [open] dan tag penutup berikutnya bernama sama.
String innerTextOf(String s, FastTag open) {
  if (open.selfClosing) return '';
  final close = s.indexOf('</', open.end);
  if (close < 0) return '';
  return unescapeXml(s.substring(open.end, close));
}

String unescapeXml(String v) {
  if (!v.contains('&')) return v;
  return v.replaceAllMapped(RegExp(r'&(#x[0-9a-fA-F]+|#\d+|amp|lt|gt|quot|apos);'), (m) {
    final e = m.group(1)!;
    switch (e) {
      case 'amp':
        return '&';
      case 'lt':
        return '<';
      case 'gt':
        return '>';
      case 'quot':
        return '"';
      case 'apos':
        return "'";
    }
    final code = e.startsWith('#x') ? int.tryParse(e.substring(2), radix: 16) : int.tryParse(e.substring(1));
    return code == null ? m.group(0)! : String.fromCharCode(code);
  });
}
