import 'package:daraja/daraja.dart';

/// Demo configuration — reads credentials from --dart-define at build time.
///
/// Run:
///   flutter run \
///     --dart-define=DARAJA_CONSUMER_KEY=<key> \
///     --dart-define=DARAJA_CONSUMER_SECRET=<secret> \
///     --dart-define=DARAJA_PASSKEY=<passkey> \
///     --dart-define=APPWRITE_ENDPOINT=https://cloud.appwrite.io/v1 \
///     --dart-define=APPWRITE_PROJECT_ID=<id> \
///     --dart-define=APPWRITE_DATABASE_ID=<db> \
///     --dart-define=APPWRITE_COLLECTION_ID=<col> \
///     --dart-define=CALLBACK_DOMAIN=<fn-domain>
const demoConfig = DarajaConfig(
  consumerKey: String.fromEnvironment('DARAJA_CONSUMER_KEY'),
  consumerSecret: String.fromEnvironment('DARAJA_CONSUMER_SECRET'),
  passkey: String.fromEnvironment('DARAJA_PASSKEY'),
  shortcode: '174379',
  environment: DarajaEnvironment.sandbox,
  appwriteEndpoint: String.fromEnvironment(
    'APPWRITE_ENDPOINT',
    defaultValue: 'https://cloud.appwrite.io/v1',
  ),
  appwriteProjectId: String.fromEnvironment('APPWRITE_PROJECT_ID'),
  appwriteDatabaseId: String.fromEnvironment('APPWRITE_DATABASE_ID'),
  appwriteCollectionId: String.fromEnvironment('APPWRITE_COLLECTION_ID'),
  callbackDomain: String.fromEnvironment('CALLBACK_DOMAIN'),
);

/// Hard-coded demo members — swap with your own sandbox numbers.
const demoMembers = [
  ('Alice', '0712000001', 'user_alice'),
  ('Bob', '0712000002', 'user_bob'),
  ('Carol', '0712000003', 'user_carol'),
];

const demoTitle = 'Lunch — KCB Plaza';
const demoTotal = 3000;
