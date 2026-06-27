import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:opds_browser/domain/local_library.dart';
import 'package:opds_browser/ui/local_library_screen.dart';

class EditBookMetadataSheet extends ConsumerStatefulWidget {
  const EditBookMetadataSheet({required this.book, super.key});
  final LibraryBook book;

  @override
  ConsumerState<EditBookMetadataSheet> createState() =>
      _EditBookMetadataSheetState();
}

class _EditBookMetadataSheetState extends ConsumerState<EditBookMetadataSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _authorCtrl;
  late final TextEditingController _seriesCtrl;
  late final TextEditingController _seriesIndexCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final meta = widget.book.meta;
    _titleCtrl = TextEditingController(text: meta.title);
    _authorCtrl = TextEditingController(text: meta.author);
    _seriesCtrl = TextEditingController(text: meta.series ?? '');
    _seriesIndexCtrl = TextEditingController(
      text: meta.seriesIndex?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _authorCtrl.dispose();
    _seriesCtrl.dispose();
    _seriesIndexCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final seriesText = _seriesCtrl.text.trim();
      final seriesIndexText = _seriesIndexCtrl.text.trim();
      final newMeta = LocalBookMetadata(
        title: _titleCtrl.text.trim(),
        author: _authorCtrl.text.trim(),
        series: seriesText.isEmpty ? null : seriesText,
        seriesIndex: seriesText.isNotEmpty && seriesIndexText.isNotEmpty
            ? int.tryParse(seriesIndexText)
            : null,
      );
      await ref
          .read(localLibraryNotifierProvider.notifier)
          .updateBook(widget.book, newMeta);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasSeries = _seriesCtrl.text.trim().isNotEmpty;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Edit book', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextFormField(
              controller: _titleCtrl,
              decoration: const InputDecoration(labelText: 'Title'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _authorCtrl,
              decoration: const InputDecoration(
                labelText: 'Author',
                helperText: 'Comma-separated for multiple authors',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _seriesCtrl,
              decoration: const InputDecoration(labelText: 'Series (optional)'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _seriesIndexCtrl,
              decoration: const InputDecoration(
                labelText: 'Series # (optional)',
              ),
              enabled: hasSeries,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
