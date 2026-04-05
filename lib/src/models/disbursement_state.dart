/// Sealed state type for the B2C disbursement lifecycle.
///
/// States flow in this order for a successful payment:
/// [DisbursementInitiating] → [DisbursementPending] → [DisbursementSuccess]
///
/// On failure or timeout:
/// [DisbursementInitiating] → [DisbursementPending] →
///   [DisbursementFailed] | [DisbursementTimeout]
///
/// On initiation error (before the request reaches Safaricom):
/// [DisbursementInitiating] only — then an exception is thrown from b2cPush().
sealed class DisbursementState {
  const DisbursementState();
}

/// The B2C request is being sent to Safaricom.
final class DisbursementInitiating extends DisbursementState {
  const DisbursementInitiating();
}

/// Safaricom accepted the B2C request. Waiting for the async result callback.
final class DisbursementPending extends DisbursementState {
  const DisbursementPending({required this.originatorConversationId});

  /// Developer-generated correlation ID, echoed by Safaricom in the callback.
  final String originatorConversationId;
}

/// Safaricom processed the disbursement and the funds were sent.
final class DisbursementSuccess extends DisbursementState {
  const DisbursementSuccess({
    required this.originatorConversationId,
    required this.conversationId,
    required this.receiptNumber,
    required this.amount,
    required this.receiverName,
    required this.settledAt,
    this.mpesaTimestamp,
  });

  /// Developer-generated correlation ID.
  final String originatorConversationId;

  /// Safaricom-generated conversation ID.
  final String conversationId;

  /// M-Pesa receipt number. Use this as the primary transaction anchor.
  final String receiptNumber;

  /// Amount disbursed in KES.
  final int amount;

  /// Recipient name as returned by Safaricom (e.g. `"0722000000 - John Doe"`).
  final String receiverName;

  /// When the Appwrite Function wrote the result to the database (UTC).
  final DateTime settledAt;

  /// When Safaricom completed the transaction (UTC). Null if Safaricom omitted
  /// `TransactionCompletedDateTime` in the callback — fall back to [settledAt].
  final DateTime? mpesaTimestamp;
}

/// Safaricom rejected or was unable to complete the disbursement.
final class DisbursementFailed extends DisbursementState {
  const DisbursementFailed({
    required this.originatorConversationId,
    required this.resultCode,
    required this.message,
  });

  final String originatorConversationId;

  /// Safaricom result code. Non-zero indicates the reason for failure.
  final int resultCode;

  /// Human-readable description from Safaricom.
  final String message;
}

/// The B2C request expired in Safaricom's queue without processing.
///
/// Unlike [DisbursementFailed], a timeout does not mean the funds were
/// definitely not sent — check your Safaricom dashboard before marking the
/// transaction as failed.
final class DisbursementTimeout extends DisbursementState {
  const DisbursementTimeout({required this.originatorConversationId});

  final String originatorConversationId;
}
