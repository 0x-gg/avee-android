import 'dart:convert';

/// Decodes provider header text that MAY be base64 (optionally
/// `base64:`-prefixed). Returns the original string unchanged when it is not
/// valid base64/utf8.
///
/// Mirrors the historical inline decode used across the app for `dropweb-*`
/// branding headers: strip an optional `base64:` prefix, normalize, then
/// `utf8.decode`. On ANY failure the ORIGINAL value (prefix included) is
/// returned. Trimming is intentionally NOT performed here — callers that need
/// it trim the result themselves.
String decodeMaybeBase64(String value) {
  var text = value;
  if (text.startsWith('base64:')) {
    text = text.substring(7);
  }
  try {
    return utf8.decode(base64.decode(base64.normalize(text)));
  } catch (_) {
    return value;
  }
}
