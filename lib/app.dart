import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:opds_browser/ui/browse_screen.dart';
import 'package:opds_browser/ui/folder_scan_screen.dart';
import 'package:opds_browser/ui/folder_tree_screen.dart';
import 'package:opds_browser/ui/setup_screen.dart';
import 'package:opds_browser/ui/settings_screen.dart';
import 'package:opds_browser/ui/start_screen.dart';
import 'package:opds_browser/ui/providers.dart';

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
    final refresher = ref.read(routerRefreshProvider);
    _router = GoRouter(
      refreshListenable: refresher,
      redirect: (context, state) {
        final container = ProviderScope.containerOf(context, listen: false);
        final settings = container.read(settingsProvider).value;
        if (settings == null) return null; // still loading
        if (settings.target == null && state.matchedLocation != '/setup') {
          return '/setup';
        }
        if (settings.target != null && state.matchedLocation == '/setup') {
          return '/';
        }
        return null;
      },
      routes: [
        GoRoute(path: '/', builder: (context, state) => const StartScreen()),
        GoRoute(
          path: '/setup',
          builder: (context, state) => const SetupScreen(),
        ),
        GoRoute(
          path: '/browse',
          builder: (_, state) {
            final params = state.uri.queryParameters;
            return BrowseScreen(
              catalogId: int.parse(params['catalogId']!),
              url: Uri.parse(params['url']!),
              navTitle: params['title'],
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
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Library coming soon'))),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'OPDS Browser',
      routerConfig: _router,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.light,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
    );
  }
}
