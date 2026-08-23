import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Registers the licence of every font bundled into the app, so it is listed
/// alongside the package licences Flutter collects on its own.
///
/// Inter ships inside the APK under the SIL Open Font License, which requires
/// the licence text to travel with the font.
void registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const [
      'Inter',
    ], await rootBundle.loadString('assets/fonts/Inter-LICENSE.txt'));
  });
}
