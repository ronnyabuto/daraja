/// Integration tests for the full STK Push payment lifecycle.
///
/// These tests require Pesa Playground running locally:
///   https://github.com/OmentaElvis/pesa-playground
///
/// Start it before running:
///   pesa-playground --port 3000
///
/// Run with:
///   flutter test test/integration/ --tags integration \
///     --dart-define=APPWRITE_ENDPOINT=https://cloud.appwrite.io/v1 \
///     --dart-define=APPWRITE_PROJECT_ID=YOUR_PROJECT_ID \
///     --dart-define=APPWRITE_DATABASE_ID=YOUR_DATABASE_ID \
///     --dart-define=APPWRITE_COLLECTION_ID=YOUR_COLLECTION_ID \
///     --dart-define=DARAJA_CONSUMER_KEY=YOUR_CONSUMER_KEY \
///     --dart-define=DARAJA_CONSUMER_SECRET=YOUR_CONSUMER_SECRET \
///     --dart-define=DARAJA_PASSKEY=YOUR_PASSKEY \
///     --dart-define=CALLBACK_DOMAIN=YOUR_CALLBACK_DOMAIN \
///     --dart-define=TEST_PHONE=0712345678 \
///     --dart-define=APPWRITE_USER_ID=YOUR_USER_ID
///
/// They are excluded from the standard test run because they require
/// external processes and a live Appwrite project. The CI unit-test job uses
/// `flutter test --exclude-tags integration` to skip these automatically.
@Tags(['integration'])
library;

import 'dart:async';

import 'package:daraja/daraja.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Configuration — replace with real sandbox credentials and a live Appwrite
// project before running. Never commit real credentials.
// ---------------------------------------------------------------------------

const _integrationConfig = DarajaConfig(
  consumerKey: String.fromEnvironment('DARAJA_CONSUMER_KEY'),
  consumerSecret: String.fromEnvironment('DARAJA_CONSUMER_SECRET'),
  passkey: String.fromEnvironment('DARAJA_PASSKEY'),
  shortcode: '174379',
  environment: DarajaEnvironment.sandbox,
  appwriteEndpoint: String.fromEnvironment('APPWRITE_ENDPOINT'),
  appwriteProjectId: String.fromEnvironment('APPWRITE_PROJECT_ID'),
  appwriteDatabaseId: String.fromEnvironment('APPWRITE_DATABASE_ID'),
  appwriteCollectionId: String.fromEnvironment('APPWRITE_COLLECTION_ID'),
  callbackDomain: String.fromEnvironment('CALLBACK_DOMAIN'),
);

const _testPhone = String.fromEnvironment(
  'TEST_PHONE',
  defaultValue: '0712345678',
);
const _testUserId = String.fromEnvironment('APPWRITE_USER_ID');

// ---------------------------------------------------------------------------

void main() {
  // Required: Appwrite's ClientIO calls path_provider in its constructor via
  // an unawaited init(), which touches a platform channel (MethodChannel).
  // Platform channels require ServicesBinding. TestWidgetsFlutterBinding
  // provides it for flutter test on desktop without a real device.
  // See: https://api.flutter.dev/flutter/flutter_test/TestWidgetsFlutterBinding/ensureInitialized.html
  TestWidgetsFlutterBinding.ensureInitialized();

  // Evaluated at registration time, before the test runner starts any test.
  // When credentials are absent, the entire group is skipped — setUp, test
  // bodies, and tearDown are never called. markTestSkipped() inside setUp()
  // is not used here because TestWidgetsFlutterBinding changes how
  // SkipException propagates, and the recovery test creates Daraja instances
  // directly in its body (bypassing setUp entirely).
  const endpoint = String.fromEnvironment('APPWRITE_ENDPOINT');
  final skipReason = endpoint.isEmpty
      ? 'Integration tests require live credentials via --dart-define.\n'
            'Run: flutter test test/integration/ --tags integration '
            '--dart-define=APPWRITE_ENDPOINT=... (see file header for all flags)'
      : null;

  Daraja? daraja;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    daraja = Daraja(config: _integrationConfig);
  });

  tearDown(() => daraja?.dispose());

  group('Full STK Push lifecycle', () {
    test(
      'happy path — PaymentSuccess received after PIN entry',
      () async {
        final stream = await daraja!.stkPush(
          phone: _testPhone,
          amount: 1,
          reference: 'INT-TEST-001',
          description: 'Integration',
          userId: _testUserId,
        );

        final states = <PaymentState>[];
        final completer = Completer<void>();

        stream.listen((state) {
          states.add(state);
          if (state is PaymentSuccess ||
              state is PaymentFailed ||
              state is PaymentCancelled ||
              state is PaymentTimeout ||
              state is PaymentError) {
            completer.complete();
          }
        });

        await completer.future.timeout(
          const Duration(seconds: 120),
          onTimeout: () => fail('Payment did not resolve within 120 seconds'),
        );

        expect(
          states,
          containsAll([isA<PaymentInitiating>(), isA<PaymentPending>()]),
        );
        expect(states.last, isA<PaymentSuccess>());

        final success = states.last as PaymentSuccess;
        expect(success.checkoutRequestId, isNotEmpty);
        expect(success.receiptNumber, isNotEmpty);
        expect(success.amount, 1);
        expect(success.settledAt, isNotNull);
      },
      timeout: const Timeout(Duration(seconds: 130)),
    );

    test(
      'user cancels — PaymentCancelled received',
      () async {
        // Pesa Playground: configure the next request to simulate cancellation
        // by setting ResultCode 1032 before initiating.

        final stream = await daraja!.stkPush(
          phone: _testPhone,
          amount: 1,
          reference: 'INT-TEST-002',
          description: 'CancelTest',
          userId: _testUserId,
        );

        final states = <PaymentState>[];
        await for (final state in stream) {
          states.add(state);
          if (state is PaymentCancelled ||
              state is PaymentSuccess ||
              state is PaymentFailed ||
              state is PaymentTimeout) {
            break;
          }
        }

        expect(states.last, isA<PaymentCancelled>());
        expect((states.last as PaymentCancelled).checkoutRequestId, isNotEmpty);
      },
      timeout: const Timeout(Duration(seconds: 130)),
    );

    test(
      'insufficient funds — PaymentFailed with correct resultCode',
      () async {
        // Pesa Playground: configure the next request to return ResultCode 1031.

        final stream = await daraja!.stkPush(
          phone: _testPhone,
          amount: 1,
          reference: 'INT-TEST-003',
          description: 'FailTest',
          userId: _testUserId,
        );

        final states = <PaymentState>[];
        await for (final state in stream) {
          states.add(state);
          if (state is PaymentFailed ||
              state is PaymentSuccess ||
              state is PaymentCancelled ||
              state is PaymentTimeout) {
            break;
          }
        }

        expect(states.last, isA<PaymentFailed>());
        final failed = states.last as PaymentFailed;
        expect(failed.resultCode, isNonZero);
        expect(failed.message, isNotEmpty);
      },
      timeout: const Timeout(Duration(seconds: 130)),
    );

    test(
      'T+90s hard timeout — PaymentTimeout emitted, not PaymentFailed',
      () async {
        // Pesa Playground: configure the next request to never send a callback.

        final stream = await daraja!.stkPush(
          phone: _testPhone,
          amount: 1,
          reference: 'INT-TEST-004',
          description: 'TimeoutTest',
          userId: _testUserId,
        );

        final states = <PaymentState>[];
        await for (final state in stream) {
          states.add(state);
          if (state is PaymentTimeout ||
              state is PaymentSuccess ||
              state is PaymentFailed ||
              state is PaymentCancelled) {
            break;
          }
        }

        expect(
          states.last,
          isA<PaymentTimeout>(),
          reason:
              'Timeout must be distinct from failure — '
              'money may have been deducted',
        );
      },
      timeout: const Timeout(Duration(seconds: 100)),
    );

    test(
      'duplicate callback — only one terminal state emitted',
      () async {
        // Pesa Playground: configure to send the SUCCESS callback twice.

        final stream = await daraja!.stkPush(
          phone: _testPhone,
          amount: 1,
          reference: 'INT-TEST-005',
          description: 'DupTest',
          userId: _testUserId,
        );

        final terminalStates = <PaymentState>[];
        await for (final state in stream) {
          if (state is PaymentSuccess ||
              state is PaymentFailed ||
              state is PaymentCancelled ||
              state is PaymentTimeout) {
            terminalStates.add(state);
          }
        }

        // The Function deduplicates via document ID conflict (409).
        // The stream must emit exactly one terminal state.
        expect(terminalStates, hasLength(1));
      },
      timeout: const Timeout(Duration(seconds: 130)),
    );

    test(
      'killed-app recovery — pending payment restored and resolved on restart',
      () async {
        // Phase 1: initiate a payment and immediately dispose (simulates kill).
        final daraja1 = Daraja(config: _integrationConfig);
        final stream1 = await daraja1.stkPush(
          phone: _testPhone,
          amount: 1,
          reference: 'INT-TEST-006',
          description: 'RecoveryTest',
          userId: _testUserId,
        );

        // Wait for pending state.
        await stream1.firstWhere((s) => s is PaymentPending);

        // Kill — CID is persisted in SharedPreferences.
        daraja1.dispose();

        // Phase 2: allow Pesa Playground to send the SUCCESS callback,
        // then create a new Daraja instance (simulates app restart).
        await Future<void>.delayed(const Duration(seconds: 5));

        final daraja2 = Daraja(config: _integrationConfig);
        addTearDown(daraja2.dispose);

        final recovered = <PaymentState>[];
        daraja2.stream.listen(
          recovered.add,
        ); // uses Daraja.stream public getter

        await daraja2.restorePendingPayment();
        await Future<void>.delayed(const Duration(seconds: 5));

        expect(recovered.first, isA<PaymentPending>());
        expect(recovered.last, isA<PaymentSuccess>());
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );
  }, skip: skipReason);
}
