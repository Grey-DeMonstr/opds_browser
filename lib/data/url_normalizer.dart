String normalizeUrl(Uri url) {
  var u = url.removeFragment();
  if ((u.scheme == 'http' && u.port == 80) ||
      (u.scheme == 'https' && u.port == 443)) {
    u = u.replace(port: null);
  }
  return u.toString();
}
