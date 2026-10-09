/// URL validation for Navigator's optional online data API.
///
/// HTTPS is required for remote hosts. Plain HTTP is accepted only for loopback
/// development servers; an API URL is configuration, not an authentication secret.
bool isSecureApiBaseUrl(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || uri.host.isEmpty || uri.userInfo.isNotEmpty ||
      uri.hasQuery || uri.hasFragment) {
    return false;
  }

  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'https') return true;

  const loopbackHosts = {'localhost', '127.0.0.1', '::1'};
  return scheme == 'http' && loopbackHosts.contains(uri.host.toLowerCase());
}
