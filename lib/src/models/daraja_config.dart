/// Selects the Safaricom API environment.
enum DarajaEnvironment {
  /// Sandbox environment for development and testing.
  /// Uses `https://sandbox.safaricom.co.ke`.
  sandbox,

  /// Live production environment.
  /// Uses `https://api.safaricom.co.ke`.
  production,
}

/// Configuration for a [Daraja] instance.
///
/// All fields are required. Pass a `const` instance to the [Daraja]
/// constructor. Store credentials securely — do not hardcode them in
/// client-side code for production apps.
///
/// ```dart
/// final daraja = Daraja(
///   config: const DarajaConfig(
///     consumerKey: 'xxx',
///     consumerSecret: 'xxx',
///     passkey: 'xxx',
///     shortcode: '174379',
///     environment: DarajaEnvironment.sandbox,
///     appwriteEndpoint: 'https://cloud.appwrite.io/v1',
///     appwriteProjectId: 'my-project',
///     appwriteDatabaseId: 'payments',
///     appwriteCollectionId: 'transactions',
///     callbackDomain: 'https://64d4d22db370ae41a32e.fra.appwrite.run',
///   ),
/// );
/// ```
final class DarajaConfig {
  const DarajaConfig({
    required this.consumerKey,
    required this.consumerSecret,
    required this.passkey,
    required this.shortcode,
    required this.environment,
    required this.appwriteEndpoint,
    required this.appwriteProjectId,
    required this.appwriteDatabaseId,
    required this.appwriteCollectionId,
    required this.callbackDomain,
  });

  /// Safaricom Daraja app consumer key.
  final String consumerKey;

  /// Safaricom Daraja app consumer secret.
  final String consumerSecret;

  /// Lipa na M-Pesa Online passkey, used to compute the request password.
  final String passkey;

  /// The M-Pesa shortcode (paybill or till) to charge.
  final String shortcode;

  /// API environment — [DarajaEnvironment.sandbox] for development,
  /// [DarajaEnvironment.production] for live payments.
  final DarajaEnvironment environment;

  /// Appwrite project endpoint, e.g. `https://cloud.appwrite.io/v1`.
  final String appwriteEndpoint;

  /// Appwrite project ID.
  final String appwriteProjectId;

  /// Appwrite database ID where payment documents are stored.
  final String appwriteDatabaseId;

  /// Appwrite collection ID for STK Push payment results.
  final String appwriteCollectionId;

  /// The public HTTPS domain of the deployed Appwrite Function.
  /// The package appends the callback path and uid query parameter automatically.
  /// Example: https://64d4d22db370ae41a32e.fra.appwrite.run
  final String callbackDomain;

  String get baseUrl => switch (environment) {
    DarajaEnvironment.sandbox => 'https://sandbox.safaricom.co.ke',
    DarajaEnvironment.production => 'https://api.safaricom.co.ke',
  };
}
