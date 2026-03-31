sealed class PaymentState {
  const PaymentState();
}

final class PaymentIdle extends PaymentState {
  const PaymentIdle();
}

final class PaymentInitiating extends PaymentState {
  const PaymentInitiating();
}

final class PaymentPending extends PaymentState {
  const PaymentPending({
    required this.checkoutRequestId,
    required this.initiatedAt,
  });

  final String checkoutRequestId;
  final DateTime initiatedAt;
}

final class PaymentSuccess extends PaymentState {
  const PaymentSuccess({
    required this.checkoutRequestId,
    required this.receiptNumber,
    required this.amount,
    required this.settledAt,
  });

  final String checkoutRequestId;
  final String receiptNumber;
  final int amount;
  final DateTime settledAt;
}

final class PaymentFailed extends PaymentState {
  const PaymentFailed({
    required this.checkoutRequestId,
    required this.resultCode,
    required this.message,
  });

  final String checkoutRequestId;
  final int resultCode;
  final String message;
}

final class PaymentCancelled extends PaymentState {
  const PaymentCancelled({required this.checkoutRequestId});

  final String checkoutRequestId;
}

/// The T+90s timeout elapsed with no callback received.
///
/// This is not a payment failure. Money may have been deducted.
/// Do not tell the user their payment failed. Show a neutral status
/// and give them a way to contact support or check their M-Pesa messages.
final class PaymentTimeout extends PaymentState {
  const PaymentTimeout({required this.checkoutRequestId});

  final String checkoutRequestId;
}

final class PaymentError extends PaymentState {
  const PaymentError({required this.message});

  final String message;
}
