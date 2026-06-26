import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:opds_browser/ui/browse_screen.dart';
import 'package:opds_browser/ui/settings_screen.dart';
import 'package:opds_browser/ui/start_screen.dart';

final _router = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const StartScreen(),
    ),
    GoRoute(
      path: '/browse',
      builder: (context, state) {
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
  ],
);

class OpdsBrowserApp extends ConsumerWidget {
  const OpdsBrowserApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef _) {
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
