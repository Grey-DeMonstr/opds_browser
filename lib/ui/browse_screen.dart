import 'package:flutter/material.dart';

class BrowseScreen extends StatelessWidget {
  final int catalogId;
  final Uri url;

  const BrowseScreen({required this.catalogId, required this.url, super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Browse')),
      body: Center(child: Text('catalogId=$catalogId\nurl=$url')),
    );
  }
}
