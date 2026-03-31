final class TokenCache {
  String? _token;
  DateTime? _expiresAt;

  static const _bufferSeconds = 60;

  String? get token {
    if (_token == null || _expiresAt == null) return null;
    if (DateTime.now().isAfter(_expiresAt!)) {
      _token = null;
      _expiresAt = null;
      return null;
    }
    return _token;
  }

  void store(String token, int expiresInSeconds) {
    _token = token;
    _expiresAt = DateTime.now().add(
      Duration(seconds: expiresInSeconds - _bufferSeconds),
    );
  }
}
