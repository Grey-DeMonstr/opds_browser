import 'dart:convert';

import 'package:opds_browser/data/app_database.dart';
import 'package:opds_browser/data/url_normalizer.dart';
import 'package:opds_browser/domain/models.dart';
import 'package:opds_browser/domain/opds_client.dart';
import 'package:opds_browser/domain/repositories.dart';
import 'package:sqflite/sqflite.dart';

class CachingFeedRepository implements FeedRepository {
  final AppDatabase _db;
  final OpdsClient _client;

  CachingFeedRepository(this._db, this._client);

  @override
  Future<CachedFeed> getFeed(
    int catalogId,
    Uri url, {
    bool forceRefresh = false,
  }) async {
    final key = normalizeUrl(url);
    final db = await _db.database;

    if (!forceRefresh) {
      final rows = await db.query(
        'feed_cache',
        where: 'catalog_id = ? AND url = ?',
        whereArgs: [catalogId, key],
      );
      if (rows.isNotEmpty) {
        final row = rows.first;
        return CachedFeed(
          feed: ParsedFeed.fromJson(
            jsonDecode(row['feed_json'] as String) as Map<String, dynamic>,
          ),
          fetchedAt: DateTime.fromMillisecondsSinceEpoch(row['fetched_at'] as int),
          fromCache: true,
        );
      }
    }

    final feed = await _fetchAllPages(url);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final now = DateTime.fromMillisecondsSinceEpoch(nowMs);
    await db.insert(
      'feed_cache',
      {
        'catalog_id': catalogId,
        'url': key,
        'feed_json': jsonEncode(feed.toJson()),
        'fetched_at': nowMs,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return CachedFeed(feed: feed, fetchedAt: now, fromCache: false);
  }

  // Minimal implementation: single-page only. Expanded in the next task.
  Future<ParsedFeed> _fetchAllPages(Uri startUrl) async {
    return _client.fetchFeed(startUrl);
  }
}
