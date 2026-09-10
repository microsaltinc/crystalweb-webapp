enum AppEnv {
  local,
  development,
  production;

  static AppEnv fromString(String value) {
    final normalized = value.trim().toLowerCase();
    for (final env in AppEnv.values) {
      if (env.name == normalized) return env;
    }
    throw ArgumentError.value(value, 'APP_ENV', 'Unsupported environment');
  }
}
