import 'package:xml/xml.dart';
import 'office_common.dart';

/// Style OpenDocument (ODT/ODS/ODP): gabungan styles.xml + content.xml.
/// Nama style bisa sama di beberapa family, jadi kunci = "family:nama".
class OdfStyles {
  final Map<String, _OdfStyle> _byKey = {};
  final Map<String, XmlElement> _defaults = {}; // family → default-style
  final Map<String, XmlElement> listStyles = {};
  final Map<String, XmlElement> masterPages = {};
  final Map<String, XmlElement> pageLayouts = {};

  OdfStyles(OfficePackage pkg) : this.forPart(pkg, 'content.xml', 'styles.xml');

  /// Style untuk sub-dokumen (mis. objek chart `Object 1/content.xml`).
  OdfStyles.forPart(OfficePackage pkg, String contentPart, String stylesPart) {
    // styles.xml dulu, lalu automatic styles content.xml (lebih spesifik)
    for (final part in [stylesPart, contentPart]) {
      final doc = pkg.xml(part);
      if (doc == null) continue;
      for (final e in doc.descendantElements) {
        switch (e.localName) {
          case 'style':
            final name = e.attr('name');
            if (name == null || e.name.prefix != 'style') continue;
            final family = e.attr('family') ?? '';
            _byKey['$family:$name'] = _OdfStyle(e, e.attr('parent-style-name'));
          case 'default-style':
            _defaults[e.attr('family') ?? ''] = e;
          case 'list-style':
            final name = e.attr('name');
            if (name != null) listStyles[name] = e;
          case 'master-page':
            final name = e.attr('name');
            if (name != null) masterPages[name] = e;
          case 'page-layout':
            final name = e.attr('name');
            if (name != null) pageLayouts[name] = e;
        }
      }
    }
  }

  XmlElement? style(String family, String? name) =>
      name == null ? null : _byKey['$family:$name']?.el;

  /// Elemen properti (mis. `text-properties`) dari default → parent → style,
  /// urut dari paling dasar ke paling spesifik.
  List<XmlElement> props(String family, String? name, String propLocal) {
    final chain = <XmlElement>[];
    final seen = <String>{};
    var cur = name;
    while (cur != null && seen.add(cur)) {
      final s = _byKey['$family:$cur'];
      if (s == null) break;
      chain.insert(0, s.el);
      cur = s.parent;
    }
    final def = _defaults[family];
    if (def != null) chain.insert(0, def);
    return [
      for (final s in chain)
        if (s.child(propLocal) != null) s.child(propLocal)!
    ];
  }
}

class _OdfStyle {
  final XmlElement el;
  final String? parent;
  _OdfStyle(this.el, this.parent);
}
