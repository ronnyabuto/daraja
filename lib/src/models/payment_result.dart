/// The result of an STK Query (polling) call.
/// Used internally by the timeout cascade — not part of the public API.
final class PaymentResult {
  const PaymentResult({
    required this.checkoutRequestId,
    required this.resultCode,
    required this.resultDesc,
  });

  final String checkoutRequestId;
  final int resultCode;
  final String resultDesc;

  bool get isSuccess => resultCode == 0;
  bool get isCancelled => resultCode == 1032;
  bool get isTimeout => resultCode == 1037;

  /// Safaricom returns 17 when the transaction is still being processed.
  /// The notifier continues waiting when this is true.
  bool get isPending => resultCode == 17;
}
