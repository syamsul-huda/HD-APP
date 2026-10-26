import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Font bawaan aplikasi yang metriknya identik dengan font Microsoft Office,
/// sehingga lebar teks, pindah baris, dan pagination sama dengan aslinya.
const kOfficeSans = 'Carlito'; // = Calibri
const kOfficeSerif = 'Caladea'; // = Cambria
const kArial = 'Liberation Sans'; // = Arial / Helvetica
const kTimes = 'Liberation Serif'; // = Times New Roman
const kCourier = 'Liberation Mono'; // = Courier New

/// Nama font di dokumen → family Flutter. `null` jika nama kosong.
String? officeFontFamily(String? name) {
  if (name == null || name.trim().isEmpty) return null;
  final f = name.toLowerCase().trim();
  if (f.contains('calibri') || f.contains('carlito') || f.startsWith('aptos') ||
      f.contains('candara') || f.contains('corbel')) {
    return kOfficeSans;
  }
  if (f.contains('cambria') || f.contains('caladea') || f.contains('constantia')) {
    return kOfficeSerif;
  }
  if (f.contains('courier') || f.contains('consolas') || f.contains('lucida console') ||
      f.contains('mono') || f.contains('menlo')) {
    return kCourier;
  }
  if (f.contains('times') || f.contains('georgia') || f.contains('garamond') ||
      f.contains('book antiqua') || f.contains('palatino') || f.contains('baskerville') ||
      f.contains('century schoolbook') || f.contains('bookman') ||
      (f.contains('serif') && !f.contains('sans'))) {
    return kTimes;
  }
  // Arial, Helvetica, Verdana, Tahoma, Segoe, Trebuchet, Arimo, Liberation Sans, …
  return kArial;
}

/// Tinggi satu spasi baris Word = (winAscent + winDescent) / unitsPerEm
/// font aslinya. Font pengganti punya metrik yang sama.
double lineFactor(String? family) => switch (family) {
      kOfficeSerif => 1.1719, // Cambria
      kArial || kTimes => 1.1499, // Arial, Times New Roman
      kCourier => 1.1328, // Courier New
      _ => 1.2207, // Calibri
    };

/// Daftarkan lisensi font (SIL OFL) ke halaman lisensi aplikasi.
void registerOfficeFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final (pkg, file) in [
      ('Carlito font', 'LICENSE-Carlito.txt'),
      ('Caladea font', 'LICENSE-Caladea.txt'),
      ('Liberation fonts', 'LICENSE-Liberation.txt'),
    ]) {
      try {
        final text = await rootBundle.loadString('assets/fonts/$file');
        yield LicenseEntryWithLineBreaks([pkg], text);
      } catch (e) {
        debugPrint('license $file: $e');
      }
    }
  });
}
