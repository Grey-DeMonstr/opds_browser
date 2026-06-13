import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/domain/time_formatter.dart';

void main() {
  final now = DateTime(2026, 6, 13, 12, 0, 0);
  DateTime t(int secondsAgo) => now.subtract(Duration(seconds: secondsAgo));

  test('< 60 s → just now', () {
    expect(formatRelativeTime(t(0), now), 'just now');
    expect(formatRelativeTime(t(59), now), 'just now');
  });

  test('< 1 h → X minutes ago', () {
    expect(formatRelativeTime(t(60), now), '1 minutes ago');
    expect(formatRelativeTime(t(90), now), '1 minutes ago');
    expect(formatRelativeTime(t(3599), now), '59 minutes ago');
  });

  test('< 24 h → X hours ago', () {
    expect(formatRelativeTime(t(3600), now), '1 hours ago');
    expect(formatRelativeTime(t(7200), now), '2 hours ago');
    expect(formatRelativeTime(t(86399), now), '23 hours ago');
  });

  test('< 30 days → X days ago', () {
    expect(formatRelativeTime(t(86400), now), '1 days ago');
    expect(formatRelativeTime(t(86400 * 7), now), '7 days ago');
    expect(formatRelativeTime(t(86400 * 29), now), '29 days ago');
  });

  test('< 365 days → X months ago', () {
    expect(formatRelativeTime(t(86400 * 30), now), '1 months ago');
    expect(formatRelativeTime(t(86400 * 60), now), '2 months ago');
    expect(formatRelativeTime(t(86400 * 364), now), '12 months ago');
  });

  test('>= 365 days → X years ago', () {
    expect(formatRelativeTime(t(86400 * 365), now), '1 years ago');
    expect(formatRelativeTime(t(86400 * 730), now), '2 years ago');
  });
}
