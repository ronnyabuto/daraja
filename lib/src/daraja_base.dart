import 'package:appwrite/appwrite.dart';

import 'client/daraja_client.dart';
import 'models/daraja_config.dart';
import 'models/payment_state.dart';
import 'notifier/payment_notifier.dart';

final class Daraja {
  Daraja({required DarajaConfig config}) : _config = config {
    final client = Client()
      ..setEndpoint(config.appwriteEndpoint)
      ..setProject(config.appwriteProjectId);

    _notifier = PaymentNotifier(
      config: config,
      databases: Databases(client),
      realtime: Realtime(client),
      darajaClient: DarajaClient(config),
    );
  }

  final DarajaConfig _config;
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

  void dispose() => _notifier.dispose();
}
