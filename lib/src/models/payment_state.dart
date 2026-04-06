/// Sealed state type for the STK Push payment lifecycle.
///
/// States flow in this order for a successful payment:
/// [PaymentInitiating] → [PaymentPending] → [PaymentSuccess]
///
/// On failure or timeout:
/// [PaymentInitiating] → [PaymentPending] →
///   [PaymentFailed] | [PaymentCancelled] | [PaymentTimeout]
///
/// On initiation error (before the STK Push reaches Safaricom):
/// [PaymentInitiating] → [PaymentError]
sealed class PaymentState {
  const PaymentState();
}

/// No payment is currently active.
final class PaymentIdle extends PaymentState {
  const PaymentIdle();
}

/// The STK Push request is being sent to Safaricom.
final class PaymentInitiating extends PaymentState {
  const PaymentInitiating();
}

/// Safaricom accepted the STK Push. The customer has been prompted to enter
/// their M-Pesa PIN. Waiting for the async callback.
final class PaymentPending extends PaymentState {
  const PaymentPending({
    required this.checkoutRequestId,
    required this.initiatedAt,
  });

  /// The Safaricom-assigned identifier for this transaction.
  final String checkoutRequestId;

  /// When the STK Push was initiated (device local time).
  final DateTime initiatedAt;
}

/// The customer entered their PIN and the payment was processed successfully.
final class PaymentSuccess extends PaymentState {
  const PaymentSuccess({
    required this.checkoutRequestId,
    required this.receiptNumber,
    required this.amount,
    required this.settledAt,
    this.mpesaTimestamp,
  });

  /// The Safaricom-assigned identifier for this transaction.
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

  /// Amount paid in KES.
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

/// The payment could not be completed. See [resultCode] and [message] for the
/// reason, or use the convenience getters for the most common failure modes.
final class PaymentFailed extends PaymentState {
  const PaymentFailed({
    required this.checkoutRequestId,
    required this.resultCode,
    required this.message,
  });

  /// The Safaricom-assigned identifier for this transaction.
  final String checkoutRequestId;

  /// Safaricom result code. Non-zero indicates the reason for failure.
  final int resultCode;

  /// Human-readable failure description from Safaricom.
  final String message;

  /// Whether the payment failed because the customer had insufficient funds
  /// (Safaricom resultCode 1).
  bool get isInsufficientFunds => resultCode == 1;

  /// Whether the payment failed because the customer entered the wrong PIN
  /// (Safaricom resultCode 2001).
  bool get isWrongPin => resultCode == 2001;

  /// Whether the subscriber is locked — either too many wrong PIN attempts
  /// or another transaction is already in progress (Safaricom resultCode 1001).
  ///
  /// This is a transient state. Prompt the customer to try again after a
  /// short delay rather than treating it as a hard failure.
  bool get isSubscriberLocked => resultCode == 1001;
}

/// The customer dismissed or cancelled the M-Pesa PIN prompt.
final class PaymentCancelled extends PaymentState {
  const PaymentCancelled({required this.checkoutRequestId});

  /// The Safaricom-assigned identifier for this transaction.
  final String checkoutRequestId;
}

/// The T+90s timeout elapsed with no callback received.
///
/// This is not a payment failure. Money may have been deducted.
/// Do not tell the user their payment failed. Show a neutral status
/// and give them a way to contact support or check their M-Pesa messages.
final class PaymentTimeout extends PaymentState {
  const PaymentTimeout({required this.checkoutRequestId});

  /// The Safaricom-assigned identifier for this transaction.
  final String checkoutRequestId;
}

/// An error occurred before or during payment initiation. The STK Push did not
/// reach the customer's phone. Check the [message] for details.
final class PaymentError extends PaymentState {
  const PaymentError({required this.message});

  /// Human-readable description of the error.
  final String message;
}
