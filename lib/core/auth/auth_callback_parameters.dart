Map<String, String> authCallbackParameters(Uri uri) {
  if (uri.fragment.isNotEmpty) {
    try {
      return Uri.splitQueryString(uri.fragment);
    } on FormatException {
      return const {};
    }
  }
  return uri.queryParameters;
}
