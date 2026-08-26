import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:opds_browser/ui/providers.dart';

/// Announces a finished download, once, wherever the reader happens to be.
///
/// It sits above the navigator rather than inside a screen: browse screens
/// stack up as you walk into a catalogue, and a listener per screen queued one
/// snackbar per level, so dismissing one only brought up the next.
class DownloadResultSnackBar extends ConsumerStatefulWidget {
  const DownloadResultSnackBar({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<DownloadResultSnackBar> createState() =>
      _DownloadResultSnackBarState();
}

class _DownloadResultSnackBarState
    extends ConsumerState<DownloadResultSnackBar> {
  Future<void> _open(DownloadDone result) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(fileOpenerProvider)
          .open(result.contentUri, result.mimeType);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not open ${result.fileName}: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(lastDownloadResultProvider, (_, result) {
      if (result == null) return;
      ref.read(lastDownloadResultProvider.notifier).clear();
      final msg = result.alreadyExisted
          ? 'Already downloaded: ${result.fileName}'
          : 'Downloaded: ${result.fileName}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          showCloseIcon: true,
          action: result.alreadyExisted
              ? null
              : SnackBarAction(label: 'Open', onPressed: () => _open(result)),
        ),
      );
    });

    return widget.child;
  }
}
