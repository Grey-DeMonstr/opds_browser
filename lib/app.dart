import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:opds_browser/ui/browse_screen.dart';
import 'package:opds_browser/ui/download_result_snack_bar.dart';
import 'package:opds_browser/ui/local_library_screen.dart';
import 'package:opds_browser/ui/folder_scan_screen.dart';
import 'package:opds_browser/ui/folder_tree_screen.dart';
import 'package:opds_browser/ui/settings_screen.dart';
import 'package:opds_browser/ui/start_screen.dart';
import 'package:opds_browser/ui/theme.dart';

class OpdsBrowserApp extends ConsumerStatefulWidget {
  const OpdsBrowserApp({super.key});

  @override
  ConsumerState<OpdsBrowserApp> createState() => _OpdsBrowserAppState();
}

class _OpdsBrowserAppState extends ConsumerState<OpdsBrowserApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (context, state) => const StartScreen()),
        GoRoute(
          path: '/browse',
          builder: (_, state) {
            final params = state.uri.queryParameters;
            return BrowseScreen(
              catalogId: int.parse(params['catalogId']!),
              url: Uri.parse(params['url']!),
              navTitle: params['title'],
              navSubtitle: params['subtitle'],
              inferredSeries: params['series'],
            );
          },
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
        ),
        GoRoute(
          path: '/folder-scan',
          builder: (_, state) {
            final params = state.uri.queryParameters;
            return FolderScanScreen(
              catalogId: int.parse(params['catalogId']!),
              url: params['url']!,
            );
          },
        ),
        GoRoute(
          path: '/folder-tree',
          builder: (context, state) => const FolderTreeScreen(),
        ),
        GoRoute(
          path: '/library',
          builder: (context, state) => const LocalLibraryScreen(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'OPDS Browser',
      routerConfig: _router,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      // Above the navigator, so a finished download is announced once rather
      // than once per stacked browse screen.
      builder: (context, child) =>
          DownloadResultSnackBar(child: child ?? const SizedBox.shrink()),
    );
  }
}
