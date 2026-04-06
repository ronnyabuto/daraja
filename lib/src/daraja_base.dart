import 'package:appwrite/appwrite.dart';

import 'client/daraja_client.dart';
import 'models/daraja_config.dart';
import 'models/payment_state.dart';
import 'notifier/payment_notifier.dart';

/// Entry point for the daraja package.
///
/// Create one instance per app, configured with [DarajaConfig], and keep it
/// alive for the lifetime of the application.
///
/// ```dart
/// final daraja = Daraja(config: myConfig);
///
/// // Subscribe before initiating — restorePendingPayment() emits on this stream.
/// daraja.stream.listen((state) { /* update UI */ });
///
/// // Restore any payment interrupted by a previous app kill.
/// await daraja.restorePendingPayment();
///
/// // Initiate a payment.
/// await daraja.stkPush(
///   phone: '0712345678',
///   amount: 100,
///   reference: 'ORDER-001',
///   description: 'Payment',
///   userId: currentUser.id,
/// );
/// ```
final class Daraja {
  /// Creates a [Daraja] instance with the given [config].
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

  /// The active configuration.
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

  /// Initiates an STK Push payment and returns the [PaymentState] stream.
  ///
  /// The returned stream is the same broadcast stream as [stream] — you do
  /// not need to listen to both.
  ///
  /// [phone] accepts all standard Kenyan formats (`07...`, `+254...`, etc.)
  /// and is normalised to `2547XXXXXXXX` internally.
  ///
  /// [reference] must be 12 characters or fewer. [description] must be 13
  /// characters or fewer. These are Safaricom API limits.
  ///
  /// Throws [DarajaAuthError] for bad OAuth credentials, [StkPushRejectedError]
  /// if Safaricom rejects the push before it reaches the customer's phone, or
  /// [DarajaException] for other HTTP/network errors.
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

  /// Releases resources. Call this when the [Daraja] instance is no longer
  /// needed (e.g. in a widget's `dispose()` or a service's `close()`).
  void dispose() => _notifier.dispose();
}
