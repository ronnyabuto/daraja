enum DarajaEnvironment { sandbox, production }

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

  final String consumerKey;
  final String consumerSecret;
  final String passkey;
  final String shortcode;
  final DarajaEnvironment environment;
  final String appwriteEndpoint;
  final String appwriteProjectId;
  final String appwriteDatabaseId;
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
