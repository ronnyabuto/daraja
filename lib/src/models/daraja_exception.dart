final class DarajaException implements Exception {
  const DarajaException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'DarajaException: $message';
}
