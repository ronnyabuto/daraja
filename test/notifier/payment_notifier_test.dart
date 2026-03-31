import 'dart:async';

import 'package:appwrite/appwrite.dart';
import 'package:daraja/src/client/daraja_client.dart';
import 'package:daraja/src/models/daraja_exception.dart';
import 'package:daraja/src/models/payment_state.dart';
import 'package:daraja/src/notifier/payment_notifier.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fixtures.dart';

class _MockDarajaClient extends Mock implements DarajaClient {}

class _MockDatabases extends Mock implements Databases {}

class _MockRealtime extends Mock implements Realtime {}

class _MockRealtimeSubscription extends Mock implements RealtimeSubscription {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockDarajaClient mockClient;
  late _MockDatabases mockDatabases;
  late _MockRealtime mockRealtime;
  late _MockRealtimeSubscription mockRealtimeSub;
  late StreamController<RealtimeMessage> realtimeController;
  late PaymentNotifier notifier;

  void stubRealtimeNeverResolves() {
    realtimeController = StreamController<RealtimeMessage>();
    when(() => mockRealtimeSub.stream)
        .thenAnswer((_) => realtimeController.stream);
    when(() => mockRealtimeSub.close()).thenReturn(null);
    when(() => mockRealtime.subscribe(any())).thenReturn(mockRealtimeSub);
  }

  void stubDatabaseNotFound() {
    when(() => mockDatabases.getDocument(
          databaseId: any(named: 'databaseId'),
          collectionId: any(named: 'collectionId'),
          documentId: any(named: 'documentId'),
        )).thenThrow(AppwriteException('Not found', 404));
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});

    mockClient = _MockDarajaClient();
    mockDatabases = _MockDatabases();
    mockRealtime = _MockRealtime();
    mockRealtimeSub = _MockRealtimeSubscription();

    stubRealtimeNeverResolves();

    notifier = PaymentNotifier(
      config: testConfig,
      databases: mockDatabases,
      realtime: mockRealtime,
      darajaClient: mockClient,
    );

    when(() => mockClient.close()).thenReturn(null);
    registerFallbackValue(AppwriteException('', 0));
  });

  tearDown(() {
    notifier.dispose();
    realtimeController.close();
  });

  Future<Stream<PaymentState>> _initiate() => notifier.initiate(
        phone: '0712345678',
        amount: 1000,
        reference: 'ORDER-001',
        description: 'Payment',
        userId: testUserId,
      );

  group('initiate()', () {
    test('emits PaymentInitiating then PaymentPending on success', () async {
      when(() => mockClient.initiateStkPush(
            phone: any(named: 'phone'),
            amount: any(named: 'amount'),
            reference: any(named: 'reference'),
            description: any(named: 'description'),
            userId: any(named: 'userId'),
          )).thenAnswer((_) async => testCid);
      stubDatabaseNotFound();

      final stream = await _initiate();
      final states = await stream.take(2).toList();

      expect(states[0], isA<PaymentInitiating>());
      expect(states[1], isA<PaymentPending>());
      expect((states[1] as PaymentPending).checkoutRequestId, testCid);
    });

    test('initiatedAt in PaymentPending is approximately now', () async {
      when(() => mockClient.initiateStkPush(
            phone: any(named: 'phone'),
            amount: any(named: 'amount'),
            reference: any(named: 'reference'),
            description: any(named: 'description'),
            userId: any(named: 'userId'),
          )).thenAnswer((_) async => testCid);
      stubDatabaseNotFound();

      final before = DateTime.now();
      final stream = await _initiate();
      final states = await stream.take(2).toList();
      final after = DateTime.now();

      final pending = states[1] as PaymentPending;
      expect(pending.initiatedAt.isAfter(before.subtract(const Duration(seconds: 1))), isTrue);
      expect(pending.initiatedAt.isBefore(after.add(const Duration(seconds: 1))), isTrue);
    });

    test('emits PaymentError when DarajaException is thrown', () async {
      when(() => mockClient.initiateStkPush(
            phone: any(named: 'phone'),
            amount: any(named: 'amount'),
            reference: any(named: 'reference'),
            description: any(named: 'description'),
            userId: any(named: 'userId'),
          )).thenThrow(const DarajaException('OAuth failed', statusCode: 401));

      final stream = await _initiate();
      final states = await stream.take(2).toList();

      expect(states[0], isA<PaymentInitiating>());
      expect(states[1], isA<PaymentError>());
      expect((states[1] as PaymentError).message, contains('OAuth failed'));
    });

    test('emits PaymentError when FormatException is thrown (invalid phone)',
        () async {
      when(() => mockClient.initiateStkPush(
            phone: any(named: 'phone'),
            amount: any(named: 'amount'),
            reference: any(named: 'reference'),
            description: any(named: 'description'),
            userId: any(named: 'userId'),
          )).thenThrow(const FormatException('Unrecognised phone format: 123'));

      final stream = await _initiate();
      final states = await stream.take(2).toList();

      expect(states[1], isA<PaymentError>());
    });

    test('emits PaymentError when ArgumentError is thrown (invalid amount)',
        () async {
      when(() => mockClient.initiateStkPush(
            phone: any(named: 'phone'),
            amount: any(named: 'amount'),
            reference: any(named: 'reference'),
            description: any(named: 'description'),
            userId: any(named: 'userId'),
          )).thenThrow(
            ArgumentError.value(-1, 'amount', 'must be a positive integer'));

      final stream = await _initiate();
      final states = await stream.take(2).toList();

      expect(states[1], isA<PaymentError>());
    });

    test('persists CheckoutRequestID to SharedPreferences on success', () async {
      when(() => mockClient.initiateStkPush(
            phone: any(named: 'phone'),
            amount: any(named: 'amount'),
            reference: any(named: 'reference'),
            description: any(named: 'description'),
            userId: any(named: 'userId'),
          )).thenAnswer((_) async => testCid);
      stubDatabaseNotFound();

      await _initiate();

      final prefs = SharedPreferencesAsync();
      expect(await prefs.getString('daraja_pending_cid'), testCid);
    });

    test('does not persist CID when initiation fails', () async {
      when(() => mockClient.initiateStkPush(
            phone: any(named: 'phone'),
            amount: any(named: 'amount'),
            reference: any(named: 'reference'),
            description: any(named: 'description'),
            userId: any(named: 'userId'),
          )).thenThrow(const DarajaException('Failed'));

      await _initiate();

      final prefs = SharedPreferencesAsync();
      expect(await prefs.getString('daraja_pending_cid'), isNull);
    });
  });

  group('timeout cascade', () {
    test('emits PaymentTimeout at exactly T+90s with no resolution', () {
      fakeAsync((fake) {
        when(() => mockClient.initiateStkPush(
              phone: any(named: 'phone'),
              amount: any(named: 'amount'),
              reference: any(named: 'reference'),
              description: any(named: 'description'),
              userId: any(named: 'userId'),
            )).thenAnswer((_) async => testCid);
        stubDatabaseNotFound();

        final states = <PaymentState>[];
        _initiate().then((stream) => stream.listen(states.add));

        fake.flushMicrotasks();
        expect(states.length, 2); // Initiating + Pending

        fake.elapse(const Duration(seconds: 89));
        expect(states.length, 2); // No timeout yet

        fake.elapse(const Duration(seconds: 2));
        expect(states.length, 3);
        expect(states.last, isA<PaymentTimeout>());
        expect((states.last as PaymentTimeout).checkoutRequestId, testCid);
      });
    });

    test('timeout does not fire after Realtime resolves the payment', () {
      fakeAsync((fake) {
        when(() => mockClient.initiateStkPush(
              phone: any(named: 'phone'),
              amount: any(named: 'amount'),
              reference: any(named: 'reference'),
              description: any(named: 'description'),
              userId: any(named: 'userId'),
            )).thenAnswer((_) async => testCid);
        stubDatabaseNotFound();

        final states = <PaymentState>[];
        _initiate().then((stream) => stream.listen(states.add));

        fake.flushMicrotasks();

        // Resolve via Realtime at T+5s.
        fake.elapse(const Duration(seconds: 5));
        realtimeController.add(realtimeMessage(status: 'SUCCESS', cid: testCid));
        fake.flushMicrotasks();

        // Advance well past T+90s.
        fake.elapse(const Duration(seconds: 100));

        // Should have: Initiating, Pending, Success — no Timeout.
        expect(states.whereType<PaymentTimeout>(), isEmpty);
        expect(states.last, isA<PaymentSuccess>());
      });
    });

    test('polls at T+10s, T+30s, and T+70s', () {
      fakeAsync((fake) {
        when(() => mockClient.initiateStkPush(
              phone: any(named: 'phone'),
              amount: any(named: 'amount'),
              reference: any(named: 'reference'),
              description: any(named: 'description'),
              userId: any(named: 'userId'),
            )).thenAnswer((_) async => testCid);
        stubDatabaseNotFound();

        _initiate();
        fake.flushMicrotasks();

        fake.elapse(const Duration(seconds: 10));
        verify(() => mockDatabases.getDocument(
              databaseId: any(named: 'databaseId'),
              collectionId: any(named: 'collectionId'),
              documentId: testCid,
            )).called(1);

        fake.elapse(const Duration(seconds: 20));
        verify(() => mockDatabases.getDocument(
              databaseId: any(named: 'databaseId'),
              collectionId: any(named: 'collectionId'),
              documentId: testCid,
            )).called(1);

        fake.elapse(const Duration(seconds: 40));
        verify(() => mockDatabases.getDocument(
              databaseId: any(named: 'databaseId'),
              collectionId: any(named: 'collectionId'),
              documentId: testCid,
            )).called(1);
      });
    });

    test('stops polling after a terminal state is reached', () {
      fakeAsync((fake) {
        when(() => mockClient.initiateStkPush(
              phone: any(named: 'phone'),
              amount: any(named: 'amount'),
              reference: any(named: 'reference'),
              description: any(named: 'description'),
              userId: any(named: 'userId'),
            )).thenAnswer((_) async => testCid);
        stubDatabaseNotFound();

        _initiate();
        fake.flushMicrotasks();

        // Resolve at T+5s via Realtime.
        fake.elapse(const Duration(seconds: 5));
        realtimeController.add(realtimeMessage(status: 'CANCELLED', cid: testCid));
        fake.flushMicrotasks();

        clearInteractions(mockDatabases);

        // Advance past all poll times — no further polls should fire.
        fake.elapse(const Duration(seconds: 100));
        verifyNever(() => mockDatabases.getDocument(
              databaseId: any(named: 'databaseId'),
              collectionId: any(named: 'collectionId'),
              documentId: any(named: 'documentId'),
            ));
      });
    });
  });

  group('terminal state cleanup', () {
    test('clears CheckoutRequestID from SharedPreferences after terminal state',
        () async {
      when(() => mockClient.initiateStkPush(
            phone: any(named: 'phone'),
            amount: any(named: 'amount'),
            reference: any(named: 'reference'),
            description: any(named: 'description'),
            userId: any(named: 'userId'),
          )).thenAnswer((_) async => testCid);

      final successDoc = successDocument();
      when(() => mockDatabases.getDocument(
            databaseId: any(named: 'databaseId'),
            collectionId: any(named: 'collectionId'),
            documentId: testCid,
          )).thenAnswer((_) async => successDoc);

      final stream = await _initiate();
      await stream.firstWhere((s) => s is PaymentSuccess);
      await Future.delayed(Duration.zero);

      final prefs = SharedPreferencesAsync();
      expect(await prefs.getString('daraja_pending_cid'), isNull);
    });

    test('a second payment can be initiated after the first resolves', () async {
      when(() => mockClient.initiateStkPush(
            phone: any(named: 'phone'),
            amount: any(named: 'amount'),
            reference: any(named: 'reference'),
            description: any(named: 'description'),
            userId: any(named: 'userId'),
          )).thenAnswer((_) async => testCid);

      when(() => mockDatabases.getDocument(
            databaseId: any(named: 'databaseId'),
            collectionId: any(named: 'collectionId'),
            documentId: testCid,
          )).thenAnswer((_) async => successDocument());

      final first = await _initiate();
      await first.firstWhere((s) => s is PaymentSuccess);
      await Future.delayed(Duration.zero);

      stubDatabaseNotFound();

      // Second payment should start cleanly.
      final second = await _initiate();
      final states = await second.take(2).toList();
      expect(states[0], isA<PaymentInitiating>());
      expect(states[1], isA<PaymentPending>());
    });
  });

  group('app lifecycle', () {
    test('polls immediately on AppLifecycleState.resumed when payment is pending',
        () async {
      when(() => mockClient.initiateStkPush(
            phone: any(named: 'phone'),
            amount: any(named: 'amount'),
            reference: any(named: 'reference'),
            description: any(named: 'description'),
            userId: any(named: 'userId'),
          )).thenAnswer((_) async => testCid);
      stubDatabaseNotFound();

      await _initiate();
      clearInteractions(mockDatabases);
      stubDatabaseNotFound();

      notifier.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future.delayed(Duration.zero);

      verify(() => mockDatabases.getDocument(
            databaseId: any(named: 'databaseId'),
            collectionId: any(named: 'collectionId'),
            documentId: testCid,
          )).called(1);
    });

    test('does not poll on resumed when no payment is pending', () async {
      notifier.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future.delayed(Duration.zero);

      verifyNever(() => mockDatabases.getDocument(
            databaseId: any(named: 'databaseId'),
            collectionId: any(named: 'collectionId'),
            documentId: any(named: 'documentId'),
          ));
    });

    test('resolves via poll on resume if payment completed while backgrounded',
        () async {
      when(() => mockClient.initiateStkPush(
            phone: any(named: 'phone'),
            amount: any(named: 'amount'),
            reference: any(named: 'reference'),
            description: any(named: 'description'),
            userId: any(named: 'userId'),
          )).thenAnswer((_) async => testCid);
      stubDatabaseNotFound();

      final stream = await _initiate();
      final states = <PaymentState>[];
      stream.listen(states.add);

      // Payment resolves while app was backgrounded.
      when(() => mockDatabases.getDocument(
            databaseId: any(named: 'databaseId'),
            collectionId: any(named: 'collectionId'),
            documentId: testCid,
          )).thenAnswer((_) async => successDocument());

      notifier.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future.delayed(Duration.zero);

      expect(states.last, isA<PaymentSuccess>());
    });
  });

  group('restorePendingPayment()', () {
    test('does nothing when no CID is in SharedPreferences', () async {
      final states = <PaymentState>[];
      notifier.stream.listen(states.add);

      await notifier.restorePendingPayment();
      await Future.delayed(Duration.zero);

      expect(states, isEmpty);
    });

    test('emits PaymentPending when CID exists and payment is still open',
        () async {
      SharedPreferences.setMockInitialValues(
          {'daraja_pending_cid': testCid});
      stubDatabaseNotFound();

      final states = <PaymentState>[];
      notifier.stream.listen(states.add);

      await notifier.restorePendingPayment();
      await Future.delayed(Duration.zero);

      expect(states.first, isA<PaymentPending>());
      expect((states.first as PaymentPending).checkoutRequestId, testCid);
    });

    test('resolves immediately when payment document exists at restore time',
        () async {
      SharedPreferences.setMockInitialValues(
          {'daraja_pending_cid': testCid});
      when(() => mockDatabases.getDocument(
            databaseId: any(named: 'databaseId'),
            collectionId: any(named: 'collectionId'),
            documentId: testCid,
          )).thenAnswer((_) async => successDocument());

      final states = <PaymentState>[];
      notifier.stream.listen(states.add);

      await notifier.restorePendingPayment();
      await Future.delayed(Duration.zero);

      expect(states, hasLength(2));
      expect(states[0], isA<PaymentPending>());
      expect(states[1], isA<PaymentSuccess>());
    });

    test('clears CID from SharedPreferences after resolving at restore time',
        () async {
      SharedPreferences.setMockInitialValues(
          {'daraja_pending_cid': testCid});
      when(() => mockDatabases.getDocument(
            databaseId: any(named: 'databaseId'),
            collectionId: any(named: 'collectionId'),
            documentId: testCid,
          )).thenAnswer((_) async => successDocument());

      await notifier.restorePendingPayment();
      await Future.delayed(Duration.zero);

      final prefs = SharedPreferencesAsync();
      expect(await prefs.getString('daraja_pending_cid'), isNull);
    });
  });
}
