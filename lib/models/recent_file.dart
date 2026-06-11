import 'dart:convert';

class RecentFile {
  final String path;
  final String name;
  final String extension;
  final int lastOpened;

  const RecentFile({
    required this.path,
    required this.name,
    required this.extension,
    required this.lastOpened,
  });

  DateTime get date => DateTime.fromMillisecondsSinceEpoch(lastOpened);

  Map<String, dynamic> toJson() => {
        'path': path,
        'name': name,
        'extension': extension,
        'lastOpened': lastOpened,
      };

  factory RecentFile.fromJson(Map<String, dynamic> j) => RecentFile(
        path: j['path'] as String,
        name: j['name'] as String,
        extension: j['extension'] as String,
        lastOpened: j['lastOpened'] as int,
      );

  static String encodeList(List<RecentFile> files) =>
      jsonEncode(files.map((f) => f.toJson()).toList());

  static List<RecentFile> decodeList(String source) =>
      (jsonDecode(source) as List)
          .map((j) => RecentFile.fromJson(j as Map<String, dynamic>))
          .toList();
}
