import 'package:appwrite/appwrite.dart';

import 'client/daraja_client.dart';
import 'models/b2c_command_id.dart';
import 'models/daraja_config.dart';
import 'models/daraja_exception.dart';
import 'models/disbursement_state.dart';
import 'models/payment_state.dart';
import 'notifier/disbursement_notifier.dart';
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
/// // Restore any B2C disbursement interrupted by a previous app kill.
/// await daraja.restorePendingDisbursement();
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

    _disbursementNotifier = DisbursementNotifier(
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
  late final DisbursementNotifier _disbursementNotifier;

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

  /// The disbursement state stream. Emits every [DisbursementState] transition,
  /// including those triggered by [restorePendingDisbursement].
  ///
  /// Subscribe to this before calling [b2cPush] if you need a global listener.
  /// The stream returned by [b2cPush] is the same broadcast stream.
  Stream<DisbursementState> get disbursementStream =>
      _disbursementNotifier.stream;

  /// Call once during app initialisation to restore any STK Push payment that
  /// was pending when the app was previously killed.
  Future<void> restorePendingPayment() => _notifier.restorePendingPayment();

  /// Call once during app initialisation to restore any B2C disbursement that
  /// was pending when the app was previously killed.
  ///
  /// Does nothing if [DarajaConfig.b2cCollectionId] is not set.
  Future<void> restorePendingDisbursement() =>
      _disbursementNotifier.restorePendingDisbursement();

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

  /// Initiates a B2C (Business to Customer) disbursement.
  ///
  /// Requires [DarajaConfig.b2cCollectionId] to be set.
  ///
  /// [securityCredential] must be generated with [SecurityCredential.generate]
  /// using Safaricom's RSA public key for your environment.
  ///
  /// Returns a broadcast stream — the same stream as [disbursementStream].
  /// Subscribe to [disbursementStream] before calling [b2cPush] if you need
  /// to observe [DisbursementInitiating], which is emitted during initiation
  /// before the returned [Future] resolves.
  ///
  /// The stream emits [DisbursementInitiating], [DisbursementPending], and
  /// then a terminal state ([DisbursementSuccess], [DisbursementFailed], or
  /// [DisbursementTimeout]).
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
  }) {
    final collectionId = _config.b2cCollectionId;
    if (collectionId == null || collectionId.isEmpty) {
      throw DarajaException(
        'b2cCollectionId must be set in DarajaConfig to use b2cPush',
      );
    }

    return _disbursementNotifier.initiate(
      phone: phone,
      amount: amount,
      initiatorName: initiatorName,
      securityCredential: securityCredential,
      commandId: commandId,
      remarks: remarks,
      occasion: occasion,
      userId: userId,
      collectionId: collectionId,
    );
  }

  /// Releases resources. Call this when the [Daraja] instance is no longer
  /// needed (e.g. in a widget's `dispose()` or a service's `close()`).
  void dispose() {
    _notifier.dispose();
    _disbursementNotifier.dispose();
    _darajaClient.close();
  }
}
