/// Base exception for all daraja errors.
///
/// Catch broadly as [DarajaException], or narrowly using a typed subclass:
/// - [DarajaAuthError] — bad credentials (OAuth 401/403)
/// - [StkPushRejectedError] — Safaricom rejected the push before it reached
///   the customer's phone (non-zero [ResponseCode])
base class DarajaException implements Exception {
  const DarajaException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'DarajaException: $message';
}

/// Thrown when OAuth token acquisition returns HTTP 401 or 403.
///
/// Usually means [DarajaConfig.consumerKey] or [DarajaConfig.consumerSecret]
/// is wrong, or the Daraja app is not enabled for the requested API.
final class DarajaAuthError extends DarajaException {
  const DarajaAuthError(super.message, {required int super.statusCode});
}

/// Thrown when the STK Push request is accepted at the HTTP level (200) but
/// Safaricom's [ResponseCode] is non-zero — meaning the business logic
/// rejected the request before a push was sent to the customer's phone.
///
/// Common [responseCode] values:
/// - `'1025'` — another transaction is already in progress for this subscriber;
///   retry after a short delay
/// - `'1001'` — unable to lock subscriber; retry after a short delay
final class StkPushRejectedError extends DarajaException {
  const StkPushRejectedError(super.message, {required this.responseCode});

  /// The Safaricom [ResponseCode] string from the initiation response
  /// (e.g. `'1025'`).
  final String responseCode;

  @override
  String toString() => 'StkPushRejectedError[$responseCode]: $message';
}

/// Thrown when the B2C request is accepted at the HTTP level (200) but
/// Safaricom's [ResponseCode] is non-zero — meaning the request was rejected
/// before entering the processing queue.
///
/// Common [responseCode] values:
/// - `'2001'` — wrong credentials; check [SecurityCredential] generation
/// - `'1001'` — unable to lock subscriber
final class B2cRejectedError extends DarajaException {
  const B2cRejectedError(super.message, {required this.responseCode});

  /// The Safaricom [ResponseCode] string from the B2C initiation response.
  final String responseCode;

  @override
  String toString() => 'B2cRejectedError[$responseCode]: $message';
}
