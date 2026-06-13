String formatRelativeTime(DateTime fetchedAt, DateTime now) {
  final diff = now.difference(fetchedAt);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} minutes ago';
  if (diff.inHours < 24) return '${diff.inHours} hours ago';
  if (diff.inDays < 30) return '${diff.inDays} days ago';
  if (diff.inDays < 365) return '${diff.inDays ~/ 30} months ago';
  return '${diff.inDays ~/ 365} years ago';
}
