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
    this.mpesaTimestamp,
  });

  final String checkoutRequestId;

  /// The M-Pesa receipt number (e.g. `NLJ7RT61SV`).
  ///
  /// This is the primary reconciliation anchor. Use it to match payments
  /// in your database and in M-Pesa transaction history.
  ///
  /// As of March 2026, Safaricom masks the `PhoneNumber` field in callbacks
  /// (`0722000***`). The daraja package never captures phone numbers —
  /// user identity is tied to the `userId` passed in [DarajaConfig] and
  /// forwarded in the callback URL. Do not use phone numbers as database keys
  /// in M-Pesa integrations.
  final String receiptNumber;

  final int amount;

  /// When the Appwrite Function processed the callback (UTC).
  final DateTime settledAt;

  /// The Safaricom-stamped transaction time (UTC), parsed from the
  /// `TransactionDate` field in `CallbackMetadata`. Null if Safaricom
  /// omitted the field (rare, but possible on partial callbacks).
  ///
  /// Prefer this over [settledAt] for reconciliation timestamps — it reflects
  /// when Safaricom completed the transaction, not when the callback arrived.
  final DateTime? mpesaTimestamp;
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
