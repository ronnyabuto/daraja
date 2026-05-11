// ignore_for_file: deprecated_member_use
import 'dart:async';

import 'package:appwrite/appwrite.dart';
import 'package:daraja/src/client/daraja_client.dart';
import 'package:daraja/src/models/b2c_command_id.dart';
import 'package:daraja/src/models/daraja_config.dart';
import 'package:daraja/src/models/daraja_exception.dart';
import 'package:daraja/src/models/disbursement_state.dart';
import 'package:daraja/src/notifier/disbursement_notifier.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../helpers/fixtures.dart';

class _MockDarajaClient extends Mock implements DarajaClient {}

class _MockDatabases extends Mock implements Databases {}

class _MockRealtime extends Mock implements Realtime {}

const _b2cConfig = DarajaConfig(
  consumerKey: 'test_consumer_key',
  consumerSecret: 'test_consumer_secret',
  passkey: 'test_passkey',
  shortcode: '174379',
  environment: DarajaEnvironment.sandbox,
  appwriteEndpoint: 'https://cloud.appwrite.io/v1',
  appwriteProjectId: 'test_project',
  appwriteDatabaseId: 'payments',
  appwriteCollectionId: 'transactions',
  callbackDomain: 'https://fn.appwrite.run',
  b2cCollectionId: testB2cCollectionId,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockDarajaClient mockClient;
  late _MockDatabases mockDatabases;
  late _MockRealtime mockRealtime;
  late StreamController<RealtimeMessage> realtimeController;
  late DisbursementNotifier notifier;

  void stubRealtimeNeverResolves() {
    realtimeController = StreamController<RealtimeMessage>();
    final sub = RealtimeSubscription(
      controller: realtimeController,
      close: () async {},
      channels: [],
      queries: [],
    );
    when(() => mockRealtime.subscribe(any())).thenReturn(sub);
  }

  void stubDatabaseNotFound() {
    when(
      () => mockDatabases.getDocument(
        databaseId: any(named: 'databaseId'),
        collectionId: any(named: 'collectionId'),
        documentId: any(named: 'documentId'),
      ),
    ).thenThrow(AppwriteException('Not found', 404));
  }

  void stubInitiateB2cSuccess() {
    when(
      () => mockClient.initiateB2c(
        originatorConversationId: any(named: 'originatorConversationId'),
        phone: any(named: 'phone'),
        amount: any(named: 'amount'),
        initiatorName: any(named: 'initiatorName'),
        securityCredential: any(named: 'securityCredential'),
        commandId: any(named: 'commandId'),
        remarks: any(named: 'remarks'),
        occasion: any(named: 'occasion'),
        userId: any(named: 'userId'),
      ),
    ).thenAnswer((_) async {});
  }

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();

    mockClient = _MockDarajaClient();
    mockDatabases = _MockDatabases();
    mockRealtime = _MockRealtime();
    stubRealtimeNeverResolves();

    notifier = DisbursementNotifier(
      config: _b2cConfig,
      databases: mockDatabases,
      realtime: mockRealtime,
      darajaClient: mockClient,
    );

    when(() => mockClient.close()).thenReturn(null);
    registerFallbackValue(AppwriteException('', 0));
    registerFallbackValue(B2cCommandId.businessPayment);
  });

  tearDown(() {
    notifier.dispose();
    realtimeController.close();
  });

  Future<Stream<DisbursementState>> initiate() => notifier.initiate(
    phone: '0712345678',
    amount: 500,
    initiatorName: 'TestInitiator',
    securityCredential: 'base64cred==',
    commandId: B2cCommandId.businessPayment,
    remarks: 'Payout',
    userId: testUserId,
    collectionId: testB2cCollectionId,
  );

  group('initiate()', () {
    test(
      'emits DisbursementInitiating then DisbursementPending on success',
      () async {
        stubInitiateB2cSuccess();
        stubDatabaseNotFound();

        final statesFuture = notifier.stream.take(2).toList();
        await initiate();
        final states = await statesFuture;

        expect(states[0], isA<DisbursementInitiating>());
        expect(states[1], isA<DisbursementPending>());
      },
    );

    test('DisbursementPending carries the generated OID', () async {
      stubInitiateB2cSuccess();
      stubDatabaseNotFound();

      final statesFuture = notifier.stream.take(2).toList();
      await initiate();
      final states = await statesFuture;

      final pending = states[1] as DisbursementPending;
      expect(pending.originatorConversationId, isNotEmpty);
      expect(
        pending.originatorConversationId,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
    });

    test('subscribes to Realtime before calling initiateB2c', () async {
      final callOrder = <String>[];

      when(
        () => mockRealtime.subscribe(any()),
      ).thenAnswer((_) {
        callOrder.add('subscribe');
        return RealtimeSubscription(
          controller: realtimeController,
          close: () async {},
          channels: [],
          queries: [],
        );
      });

      when(
        () => mockClient.initiateB2c(
          originatorConversationId: any(named: 'originatorConversationId'),
          phone: any(named: 'phone'),
          amount: any(named: 'amount'),
          initiatorName: any(named: 'initiatorName'),
          securityCredential: any(named: 'securityCredential'),
          commandId: any(named: 'commandId'),
          remarks: any(named: 'remarks'),
          occasion: any(named: 'occasion'),
          userId: any(named: 'userId'),
        ),
      ).thenAnswer((_) async {
        callOrder.add('initiate');
      });

      await initiate();

      expect(callOrder, ['subscribe', 'initiate']);
    });

    test('persists OID to SharedPreferences on success', () async {
      stubInitiateB2cSuccess();
      stubDatabaseNotFound();

      await initiate();

      final prefs = SharedPreferencesAsync();
      expect(await prefs.getString('daraja_pending_b2c_oid'), isNotEmpty);
    });

    test('does not persist OID when initiateB2c throws', () async {
      when(
        () => mockClient.initiateB2c(
          originatorConversationId: any(named: 'originatorConversationId'),
          phone: any(named: 'phone'),
          amount: any(named: 'amount'),
          initiatorName: any(named: 'initiatorName'),
          securityCredential: any(named: 'securityCredential'),
          commandId: any(named: 'commandId'),
          remarks: any(named: 'remarks'),
          occasion: any(named: 'occasion'),
          userId: any(named: 'userId'),
        ),
      ).thenThrow(const B2cRejectedError('Rejected', responseCode: '2001'));

      await expectLater(initiate(), throwsA(isA<B2cRejectedError>()));

      final prefs = SharedPreferencesAsync();
      expect(await prefs.getString('daraja_pending_b2c_oid'), isNull);
    });
  });

  group('timeout cascade', () {
    test('emits DisbursementTimeout at T+90s with no resolution', () {
      fakeAsync((fake) {
        stubInitiateB2cSuccess();
        stubDatabaseNotFound();

        final states = <DisbursementState>[];
        notifier.stream.listen(states.add);
        initiate();

        fake.flushMicrotasks();
        expect(states.length, 2); // Initiating + Pending

        fake.elapse(const Duration(seconds: 89));
        expect(states.length, 2);

        fake.elapse(const Duration(seconds: 2));
        expect(states.length, 3);
        expect(states.last, isA<DisbursementTimeout>());
      });
    });

    test('timeout does not fire after Realtime resolves the disbursement', () {
      fakeAsync((fake) {
        stubInitiateB2cSuccess();
        stubDatabaseNotFound();

        final states = <DisbursementState>[];
        initiate().then((stream) => stream.listen(states.add));

        fake.flushMicrotasks();

        fake.elapse(const Duration(seconds: 5));
        realtimeController.add(
          b2cRealtimeMessage(status: 'SUCCESS'),
        );
        fake.flushMicrotasks();

        fake.elapse(const Duration(seconds: 100));

        expect(states.whereType<DisbursementTimeout>(), isEmpty);
        expect(states.last, isA<DisbursementSuccess>());
      });
    });

    test('polls at T+15s, T+45s, and T+75s', () {
      fakeAsync((fake) {
        stubInitiateB2cSuccess();
        stubDatabaseNotFound();

        initiate();
        fake.flushMicrotasks();

        fake.elapse(const Duration(seconds: 15));
        verify(
          () => mockDatabases.getDocument(
            databaseId: any(named: 'databaseId'),
            collectionId: any(named: 'collectionId'),
            documentId: any(named: 'documentId'),
          ),
        ).called(1);

        fake.elapse(const Duration(seconds: 30));
        verify(
          () => mockDatabases.getDocument(
            databaseId: any(named: 'databaseId'),
            collectionId: any(named: 'collectionId'),
            documentId: any(named: 'documentId'),
          ),
        ).called(1);

        fake.elapse(const Duration(seconds: 30));
        verify(
          () => mockDatabases.getDocument(
            databaseId: any(named: 'databaseId'),
            collectionId: any(named: 'collectionId'),
            documentId: any(named: 'documentId'),
          ),
        ).called(1);
      });
    });

    test('stops polling after a terminal state is reached', () {
      fakeAsync((fake) {
        stubInitiateB2cSuccess();
        stubDatabaseNotFound();

        initiate();
        fake.flushMicrotasks();

        fake.elapse(const Duration(seconds: 5));
        realtimeController.add(b2cRealtimeMessage(status: 'SUCCESS'));
        fake.flushMicrotasks();

        clearInteractions(mockDatabases);

        fake.elapse(const Duration(seconds: 100));
        verifyNever(
          () => mockDatabases.getDocument(
            databaseId: any(named: 'databaseId'),
            collectionId: any(named: 'collectionId'),
            documentId: any(named: 'documentId'),
          ),
        );
      });
    });
  });

  group('terminal state cleanup', () {
    test('clears OID from SharedPreferences after terminal state', () async {
      stubInitiateB2cSuccess();

      when(
        () => mockDatabases.getDocument(
          databaseId: any(named: 'databaseId'),
          collectionId: any(named: 'collectionId'),
          documentId: any(named: 'documentId'),
        ),
      ).thenAnswer((_) async => b2cSuccessDocument());

      final stream = await initiate();
      await stream.firstWhere((s) => s is DisbursementSuccess);
      await Future<void>.delayed(Duration.zero);

      final prefs = SharedPreferencesAsync();
      expect(await prefs.getString('daraja_pending_b2c_oid'), isNull);
    });
  });

  group('app lifecycle', () {
    test(
      'polls immediately on AppLifecycleState.resumed when disbursement is pending',
      () async {
        stubInitiateB2cSuccess();
        stubDatabaseNotFound();

        await initiate();
        clearInteractions(mockDatabases);
        stubDatabaseNotFound();

        notifier.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await Future<void>.delayed(Duration.zero);

        verify(
          () => mockDatabases.getDocument(
            databaseId: any(named: 'databaseId'),
            collectionId: any(named: 'collectionId'),
            documentId: any(named: 'documentId'),
          ),
        ).called(1);
      },
    );

    test('does not poll on resumed when no disbursement is pending', () async {
      notifier.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);

      verifyNever(
        () => mockDatabases.getDocument(
          databaseId: any(named: 'databaseId'),
          collectionId: any(named: 'collectionId'),
          documentId: any(named: 'documentId'),
        ),
      );
    });

    test(
      'resolves via poll on resume if disbursement completed while backgrounded',
      () async {
        stubInitiateB2cSuccess();
        stubDatabaseNotFound();

        final stream = await initiate();
        final states = <DisbursementState>[];
        stream.listen(states.add);

        when(
          () => mockDatabases.getDocument(
            databaseId: any(named: 'databaseId'),
            collectionId: any(named: 'collectionId'),
            documentId: any(named: 'documentId'),
          ),
        ).thenAnswer((_) async => b2cSuccessDocument());

        notifier.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await Future<void>.delayed(Duration.zero);

        expect(states.last, isA<DisbursementSuccess>());
      },
    );
  });

  group('restorePendingDisbursement()', () {
    test('does nothing when no OID is in SharedPreferences', () async {
      final states = <DisbursementState>[];
      notifier.stream.listen(states.add);

      await notifier.restorePendingDisbursement();
      await Future<void>.delayed(Duration.zero);

      expect(states, isEmpty);
    });

    test(
      'does nothing when b2cCollectionId is not configured',
      () async {
        final noB2cNotifier = DisbursementNotifier(
          config: testConfig, // no b2cCollectionId
          databases: mockDatabases,
          realtime: mockRealtime,
          darajaClient: mockClient,
        );
        addTearDown(noB2cNotifier.dispose);

        SharedPreferencesAsyncPlatform.instance =
            InMemorySharedPreferencesAsync.withData({
              'daraja_pending_b2c_oid': testOriginatorConversationId,
            });

        final states = <DisbursementState>[];
        noB2cNotifier.stream.listen(states.add);

        await noB2cNotifier.restorePendingDisbursement();
        await Future<void>.delayed(Duration.zero);

        expect(states, isEmpty);
      },
    );

    test(
      'emits DisbursementPending when OID exists and disbursement is still open',
      () async {
        SharedPreferencesAsyncPlatform.instance =
            InMemorySharedPreferencesAsync.withData({
              'daraja_pending_b2c_oid': testOriginatorConversationId,
            });
        stubDatabaseNotFound();

        final states = <DisbursementState>[];
        notifier.stream.listen(states.add);

        await notifier.restorePendingDisbursement();
        await Future<void>.delayed(Duration.zero);

        expect(states.first, isA<DisbursementPending>());
        expect(
          (states.first as DisbursementPending).originatorConversationId,
          testOriginatorConversationId,
        );
      },
    );

    test(
      'resolves immediately when disbursement document exists at restore time',
      () async {
        SharedPreferencesAsyncPlatform.instance =
            InMemorySharedPreferencesAsync.withData({
              'daraja_pending_b2c_oid': testOriginatorConversationId,
            });

        when(
          () => mockDatabases.getDocument(
            databaseId: any(named: 'databaseId'),
            collectionId: any(named: 'collectionId'),
            documentId: testOriginatorConversationId,
          ),
        ).thenAnswer((_) async => b2cSuccessDocument());

        final states = <DisbursementState>[];
        notifier.stream.listen(states.add);

        await notifier.restorePendingDisbursement();
        await Future<void>.delayed(Duration.zero);

        expect(states, hasLength(2));
        expect(states[0], isA<DisbursementPending>());
        expect(states[1], isA<DisbursementSuccess>());
      },
    );

    test(
      'clears OID from SharedPreferences after resolving at restore time',
      () async {
        SharedPreferencesAsyncPlatform.instance =
            InMemorySharedPreferencesAsync.withData({
              'daraja_pending_b2c_oid': testOriginatorConversationId,
            });

        when(
          () => mockDatabases.getDocument(
            databaseId: any(named: 'databaseId'),
            collectionId: any(named: 'collectionId'),
            documentId: testOriginatorConversationId,
          ),
        ).thenAnswer((_) async => b2cSuccessDocument());

        await notifier.restorePendingDisbursement();
        await Future<void>.delayed(Duration.zero);

        final prefs = SharedPreferencesAsync();
        expect(await prefs.getString('daraja_pending_b2c_oid'), isNull);
      },
    );
  });
}
