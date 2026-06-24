import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:opds_browser/app.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  runApp(const ProviderScope(child: OpdsBrowserApp()));
}
