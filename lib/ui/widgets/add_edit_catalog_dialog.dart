import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/domain/opds_client.dart';
import 'package:opds_browser/ui/providers.dart';

class AddEditCatalogDialog extends ConsumerStatefulWidget {
  final Catalog? catalog;

  const AddEditCatalogDialog({this.catalog, super.key});

  @override
  ConsumerState<AddEditCatalogDialog> createState() =>
      _AddEditCatalogDialogState();
}

class _AddEditCatalogDialogState extends ConsumerState<AddEditCatalogDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _urlCtrl;
  bool _probing = false;
  String? _probeError;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.catalog?.title ?? '');
    _urlCtrl = TextEditingController(
      text: widget.catalog?.rootUrl.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  Uri _parseUrl(String raw) {
    final trimmed = raw.trim();
    return trimmed.contains('://')
        ? Uri.parse(trimmed)
        : Uri.parse('https://$trimmed');
  }

  Future<void> _submit({bool skipProbe = false}) async {
    if (!_formKey.currentState!.validate()) return;

    final title = _titleCtrl.text.trim();
    final url = _parseUrl(_urlCtrl.text);

    if (!skipProbe) {
      setState(() {
        _probing = true;
        _probeError = null;
      });
      bool ok;
      try {
        ok = await ref.read(opdsClientProvider).probe(url);
      } on OpdsException catch (e) {
        if (mounted) {
          setState(() {
            _probing = false;
            _probeError = e.message;
          });
        }
        return;
      }
      if (mounted) {
        setState(() {
          _probing = false;
        });
      }
      if (!ok) {
        if (mounted) {
          setState(() {
            _probeError = 'Not a supported OPDS catalogue';
          });
        }
        return;
      }
    }

    if (widget.catalog == null) {
      await ref.read(catalogsProvider.notifier).add(title, url);
    } else {
      await ref
          .read(catalogsProvider.notifier)
          .updateCatalog(
            Catalog(
              id: widget.catalog!.id,
              title: title,
              rootUrl: url,
              protocol: widget.catalog!.protocol,
            ),
          );
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.catalog != null;

    return AlertDialog(
      title: Text(isEdit ? 'Edit catalogue' : 'Add catalogue'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _titleCtrl,
              decoration: const InputDecoration(labelText: 'Title'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Title is required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _urlCtrl,
              decoration: const InputDecoration(labelText: 'URL'),
              keyboardType: TextInputType.url,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'URL is required' : null,
            ),
            if (_probeError != null) ...[
              const SizedBox(height: 8),
              Text(
                _probeError!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 13,
                ),
              ),
              TextButton(
                onPressed: _probing ? null : () => _submit(skipProbe: true),
                child: const Text('Save anyway'),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _probing ? null : _submit,
          child: _probing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
