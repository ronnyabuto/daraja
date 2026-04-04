import 'dart:async';

import 'package:appwrite/appwrite.dart';

import '../models/daraja_config.dart';
import '../models/payment_state.dart';

class PaymentSubscription {
  PaymentSubscription({
    required Databases databases,
    required Realtime realtime,
    required DarajaConfig config,
    required String checkoutRequestId,
  }) : _databases = databases,
       _realtime = realtime,
       _config = config,
       _checkoutRequestId = checkoutRequestId;

  final Databases _databases;
  final Realtime _realtime;
  final DarajaConfig _config;
  final String _checkoutRequestId;

  RealtimeSubscription? _subscription;

  Stream<PaymentState> get stream async* {
    _subscription = _realtime.subscribe([
      'databases.${_config.appwriteDatabaseId}'
          '.collections.${_config.appwriteCollectionId}'
          '.documents.$_checkoutRequestId',
    ]);

    await for (final message in _subscription!.stream) {
      final isRelevant = message.events.any(
        (e) => e.contains('.create') || e.contains('.update'),
      );
      if (!isRelevant) continue;

      final state = _parseDocument(message.payload, _checkoutRequestId);
      if (state != null) {
        yield state;
        return;
      }
    }
  }

  /// Called after a WebSocket reconnection to check if the payment resolved
  /// during the gap. Returns the terminal state if found, null if still pending.
  Future<PaymentState?> poll() async {
    try {
      // ignore: deprecated_member_use
      final doc = await _databases.getDocument(
        databaseId: _config.appwriteDatabaseId,
        collectionId: _config.appwriteCollectionId,
        documentId: _checkoutRequestId,
      );
      return _parseDocument(doc.data, _checkoutRequestId);
    } on AppwriteException catch (e) {
      if (e.code == 404) return null;
      rethrow;
    }
  }

  void close() {
    final sub = _subscription;
    if (sub != null) unawaited(sub.close());
  }
}

PaymentState? _parseDocument(
  Map<String, dynamic> data,
  String checkoutRequestId,
) {
  final status = data['status'] as String?;
  return switch (status) {
    'SUCCESS' => PaymentSuccess(
      checkoutRequestId: checkoutRequestId,
      receiptNumber: data['receipt'] as String,
      amount: data['amount'] as int,
      settledAt: DateTime.parse(data['settledAt'] as String),
    ),
    'FAILED' => PaymentFailed(
      checkoutRequestId: checkoutRequestId,
      resultCode: data['resultCode'] as int,
      message: data['failureReason'] as String? ?? '',
    ),
    'CANCELLED' => PaymentCancelled(checkoutRequestId: checkoutRequestId),
    'TIMEOUT' => PaymentTimeout(checkoutRequestId: checkoutRequestId),
    _ => null,
  };
}
