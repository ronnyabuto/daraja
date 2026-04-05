import 'dart:async';
import 'dart:math';

import 'package:appwrite/appwrite.dart';

import 'client/daraja_client.dart';
import 'models/b2c_command_id.dart';
import 'models/daraja_config.dart';
import 'models/daraja_exception.dart';
import 'models/disbursement_state.dart';
import 'models/payment_state.dart';
import 'notifier/payment_notifier.dart';

final class Daraja {
  Daraja({required DarajaConfig config}) : _config = config {
    final appwriteClient = Client()
      ..setEndpoint(config.appwriteEndpoint)
      ..setProject(config.appwriteProjectId);

    _databases = Databases(appwriteClient);
    _realtime = Realtime(appwriteClient);
    _darajaClient = DarajaClient(config);

    _notifier = PaymentNotifier(
      config: config,
      databases: _databases,
      realtime: _realtime,
      darajaClient: _darajaClient,
    );
  }

  final DarajaConfig _config;
  late final DarajaClient _darajaClient;
  late final Databases _databases;
  late final Realtime _realtime;
  late final PaymentNotifier _notifier;

  DarajaConfig get config => _config;

  /// The payment state stream. Emits every [PaymentState] transition,
  /// including those triggered by [restorePendingPayment].
  ///
  /// Subscribe to this before calling [restorePendingPayment] or [stkPush]
  /// if you need a global listener (e.g. a top-level payment status widget).
  /// The stream returned by [stkPush] is the same broadcast stream — you do
  /// not need both.
  Stream<PaymentState> get stream => _notifier.stream;

  /// Call once during app initialisation to restore any payment that was
  /// pending when the app was previously killed.
  Future<void> restorePendingPayment() => _notifier.restorePendingPayment();

  Future<Stream<PaymentState>> stkPush({
    required String phone,
    required int amount,
    required String reference,
    required String description,
    required String userId,
  }) => _notifier.initiate(
    phone: phone,
    amount: amount,
    reference: reference,
    description: description,
    userId: userId,
  );

  /// Initiates a B2C (Business to Customer) disbursement.
  ///
  /// Requires [DarajaConfig.b2cCollectionId] to be set.
  ///
  /// [securityCredential] must be generated with [SecurityCredential.generate]
  /// using Safaricom's RSA public key for your environment.
  ///
  /// Returns a broadcast stream that emits [DisbursementInitiating],
  /// [DisbursementPending], and then a terminal state
  /// ([DisbursementSuccess], [DisbursementFailed], or [DisbursementTimeout]).
  /// The stream closes after the terminal state.
  ///
  /// Subscribe to the returned stream immediately — initial states are emitted
  /// on the next microtask.
  ///
  /// Throws [DarajaAuthError], [B2cRejectedError], [FormatException], or
  /// [ArgumentError] if the request fails before reaching Safaricom.
  Future<Stream<DisbursementState>> b2cPush({
    required String phone,
    required int amount,
    required String initiatorName,
    required String securityCredential,
    required String remarks,
    B2cCommandId commandId = B2cCommandId.businessPayment,
    String? occasion,
    required String userId,
  }) async {
    final b2cCollectionId = _config.b2cCollectionId;
    if (b2cCollectionId == null || b2cCollectionId.isEmpty) {
      throw DarajaException(
        'b2cCollectionId must be set in DarajaConfig to use b2cPush',
      );
    }

    final originatorConversationId = _uuid();

    // May throw DarajaAuthError, B2cRejectedError, FormatException,
    // or ArgumentError — let them propagate to the caller.
    await _darajaClient.initiateB2c(
      originatorConversationId: originatorConversationId,
      phone: phone,
      amount: amount,
      initiatorName: initiatorName,
      securityCredential: securityCredential,
      commandId: commandId,
      remarks: remarks,
      occasion: occasion,
      userId: userId,
    );

    final controller = StreamController<DisbursementState>.broadcast();

    void emit(DisbursementState state) {
      if (!controller.isClosed) controller.add(state);
    }

    void cleanup([Timer? timer, RealtimeSubscription? sub]) {
      timer?.cancel();
      if (sub != null) unawaited(sub.close());
      if (!controller.isClosed) unawaited(controller.close());
    }

    // Emit initial states on the next microtask so the caller has a chance
    // to subscribe synchronously before events arrive.
    scheduleMicrotask(() {
      emit(DisbursementInitiating());
      emit(DisbursementPending(originatorConversationId: originatorConversationId));
    });

    final channel =
        'databases.${_config.appwriteDatabaseId}'
        '.collections.$b2cCollectionId'
        '.documents.$originatorConversationId';

    final realtimeSub = _realtime.subscribe([channel]);

    Timer? timeoutTimer;

    realtimeSub.stream.listen((message) {
      final isRelevant = message.events.any(
        (e) => e.contains('.create') || e.contains('.update'),
      );
      if (!isRelevant) return;

      final state = _parseDisbursementDocument(
        message.payload,
        originatorConversationId,
      );
      if (state == null) return;

      emit(state);
      cleanup(timeoutTimer, realtimeSub);
    });

    timeoutTimer = Timer(const Duration(seconds: 90), () {
      emit(DisbursementTimeout(originatorConversationId: originatorConversationId));
      cleanup(null, realtimeSub);
    });

    return controller.stream;
  }

  void dispose() {
    _notifier.dispose();
  }
}

DisbursementState? _parseDisbursementDocument(
  Map<String, dynamic> data,
  String originatorConversationId,
) {
  final status = data['status'] as String?;
  return switch (status) {
    'SUCCESS' => DisbursementSuccess(
      originatorConversationId: originatorConversationId,
      conversationId: data['conversationId'] as String? ?? '',
      receiptNumber: data['receipt'] as String,
      amount: data['amount'] as int,
      receiverName: data['receiverName'] as String? ?? '',
      settledAt: DateTime.parse(data['settledAt'] as String),
      mpesaTimestamp: data['mpesaTimestamp'] != null
          ? DateTime.parse(data['mpesaTimestamp'] as String)
          : null,
    ),
    'FAILED' => DisbursementFailed(
      originatorConversationId: originatorConversationId,
      resultCode: data['resultCode'] as int,
      message: data['failureReason'] as String? ?? '',
    ),
    'TIMEOUT' => DisbursementTimeout(
      originatorConversationId: originatorConversationId,
    ),
    _ => null,
  };
}

String _uuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 1
  final hex = bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}'
      '-${hex.substring(12, 16)}-${hex.substring(16, 20)}'
      '-${hex.substring(20)}';
}
