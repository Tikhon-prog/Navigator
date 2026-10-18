/// URL validation for the optional online data API of «Поколение».
///
/// Remote API traffic must use HTTPS. A client-side API URL is configuration,
/// not an authentication secret.
bool isSecureApiBaseUrl(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || uri.host.isEmpty || uri.userInfo.isNotEmpty ||
      uri.hasQuery || uri.hasFragment) {
    return false;
  }

  return uri.scheme.toLowerCase() == 'https';
}
