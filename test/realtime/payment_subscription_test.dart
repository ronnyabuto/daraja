import 'dart:async';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as appwrite_models;
import 'package:daraja/src/models/payment_state.dart';
import 'package:daraja/src/realtime/payment_subscription.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/fixtures.dart';

class _MockDatabases extends Mock implements Databases {}

class _MockRealtime extends Mock implements Realtime {}

void main() {
  late _MockDatabases mockDatabases;
  late _MockRealtime mockRealtime;
  late PaymentSubscription subscription;

  setUp(() {
    mockDatabases = _MockDatabases();
    mockRealtime = _MockRealtime();
    subscription = PaymentSubscription(
      databases: mockDatabases,
      realtime: mockRealtime,
      config: testConfig,
      checkoutRequestId: testCid,
    );
  });

  group('poll()', () {
    void stubGetDocument(appwrite_models.Document doc) {
      when(
        () => mockDatabases.getDocument(
          databaseId: testConfig.appwriteDatabaseId,
          collectionId: testConfig.appwriteCollectionId,
          documentId: testCid,
        ),
      ).thenAnswer((_) async => doc);
    }

    test(
      'returns PaymentSuccess with correct fields when status is SUCCESS',
      () async {
        final settledAt = DateTime.utc(2026, 3, 31, 12, 0, 0);
        stubGetDocument(successDocument(settledAt: settledAt));

        final state = await subscription.poll();

        expect(state, isA<PaymentSuccess>());
        final s = state as PaymentSuccess;
        expect(s.checkoutRequestId, testCid);
        expect(s.receiptNumber, testReceipt);
        expect(s.amount, 1000);
        expect(s.settledAt, settledAt);
      },
    );

    test(
      'returns PaymentFailed with resultCode and message when status is FAILED',
      () async {
        stubGetDocument(
          failedDocument(resultCode: 1031, failureReason: 'Insufficient funds'),
        );

        final state = await subscription.poll();

        expect(state, isA<PaymentFailed>());
        final f = state as PaymentFailed;
        expect(f.checkoutRequestId, testCid);
        expect(f.resultCode, 1031);
        expect(f.message, 'Insufficient funds');
      },
    );

    test('returns PaymentCancelled when status is CANCELLED', () async {
      stubGetDocument(cancelledDocument());

      final state = await subscription.poll();

      expect(state, isA<PaymentCancelled>());
      expect((state as PaymentCancelled).checkoutRequestId, testCid);
    });

    test('returns PaymentTimeout when status is TIMEOUT', () async {
      stubGetDocument(timeoutDocument());

      final state = await subscription.poll();

      expect(state, isA<PaymentTimeout>());
      expect((state as PaymentTimeout).checkoutRequestId, testCid);
    });

    test(
      'returns null when status is null — document exists but not yet resolved',
      () async {
        final now = DateTime.utc(2026, 3, 31);
        when(
          () => mockDatabases.getDocument(
            databaseId: any(named: 'databaseId'),
            collectionId: any(named: 'collectionId'),
            documentId: any(named: 'documentId'),
          ),
        ).thenAnswer(
          (_) async => appwrite_models.Document(
            $id: testCid,
            $sequence: '1',
            $collectionId: 'transactions',
            $databaseId: 'payments',
            $createdAt: now.toIso8601String(),
            $updatedAt: now.toIso8601String(),
            $permissions: [],
            data: {'checkoutRequestId': testCid, 'status': null},
          ),
        );

        final state = await subscription.poll();
        expect(state, isNull);
      },
    );

    test(
      'returns null on 404 — document not yet written by the function',
      () async {
        when(
          () => mockDatabases.getDocument(
            databaseId: any(named: 'databaseId'),
            collectionId: any(named: 'collectionId'),
            documentId: any(named: 'documentId'),
          ),
        ).thenThrow(AppwriteException('Document not found', 404));

        final state = await subscription.poll();
        expect(state, isNull);
      },
    );

    test('rethrows AppwriteException for non-404 errors', () async {
      when(
        () => mockDatabases.getDocument(
          databaseId: any(named: 'databaseId'),
          collectionId: any(named: 'collectionId'),
          documentId: any(named: 'documentId'),
        ),
      ).thenThrow(AppwriteException('Internal server error', 500));

      expect(subscription.poll(), throwsA(isA<AppwriteException>()));
    });

    test('queries the correct database, collection, and document', () async {
      stubGetDocument(successDocument());

      await subscription.poll();

      verify(
        () => mockDatabases.getDocument(
          databaseId: testConfig.appwriteDatabaseId,
          collectionId: testConfig.appwriteCollectionId,
          documentId: testCid,
        ),
      ).called(1);
    });
  });

  group('stream', () {
    late StreamController<RealtimeMessage> realtimeController;

    setUp(() {
      realtimeController = StreamController<RealtimeMessage>();
      final sub = RealtimeSubscription(
        controller: realtimeController,
        close: () async {},
        channels: [],
        queries: [],
      );
      when(() => mockRealtime.subscribe(any())).thenReturn(sub);
    });

    tearDown(() => realtimeController.close());

    test('subscribes to the exact document channel', () async {
      realtimeController.add(realtimeMessage(status: 'SUCCESS', cid: testCid));

      await subscription.stream.first;

      final captured = verify(
        () => mockRealtime.subscribe(captureAny()),
      ).captured;
      final channels = (captured.single as List<Object>).cast<String>();
      expect(
        channels.single,
        'databases.${testConfig.appwriteDatabaseId}.collections.${testConfig.appwriteCollectionId}.documents.$testCid',
      );
    });

    test('emits PaymentSuccess and closes on SUCCESS create event', () async {
      realtimeController.add(
        realtimeMessage(status: 'SUCCESS', cid: testCid, amount: 750),
      );

      final states = await subscription.stream.toList();

      expect(states, hasLength(1));
      expect(states.single, isA<PaymentSuccess>());
      expect((states.single as PaymentSuccess).amount, 750);
    });

    test('emits PaymentFailed on FAILED update event', () async {
      realtimeController.add(
        realtimeMessage(
          status: 'FAILED',
          cid: testCid,
          resultCode: 1031,
          failureReason: 'Insufficient funds',
          eventType: 'update',
        ),
      );

      final state = await subscription.stream.first;

      expect(state, isA<PaymentFailed>());
      expect((state as PaymentFailed).resultCode, 1031);
    });

    test('emits PaymentCancelled on CANCELLED event', () async {
      realtimeController.add(
        realtimeMessage(status: 'CANCELLED', cid: testCid),
      );

      final state = await subscription.stream.first;
      expect(state, isA<PaymentCancelled>());
    });

    test('emits PaymentTimeout on TIMEOUT event', () async {
      realtimeController.add(realtimeMessage(status: 'TIMEOUT', cid: testCid));

      final state = await subscription.stream.first;
      expect(state, isA<PaymentTimeout>());
    });

    test('ignores events that are not create or update', () async {
      // A delete event — should be skipped.
      realtimeController.add(
        RealtimeMessage(
          events: [
            'databases.payments.collections.transactions.documents.$testCid.delete',
          ],
          payload: {'checkoutRequestId': testCid, 'status': 'SUCCESS'},
          channels: [],
          timestamp: '2026-03-31T12:00:00.000Z',
        ),
      );

      // Then a real SUCCESS event.
      realtimeController.add(realtimeMessage(status: 'SUCCESS', cid: testCid));

      final states = await subscription.stream.toList();

      // Only the SUCCESS event should have been emitted.
      expect(states, hasLength(1));
      expect(states.single, isA<PaymentSuccess>());
    });

    test('does not emit for an unresolved status in a Realtime event', () async {
      // Simulate a message where the status is not a terminal value.
      // The stream should not yield and should continue waiting.
      realtimeController.add(
        RealtimeMessage(
          events: [
            'databases.payments.collections.transactions.documents.$testCid.update',
          ],
          payload: {'checkoutRequestId': testCid, 'status': null},
          channels: [],
          timestamp: '2026-03-31T12:00:00.000Z',
        ),
      );

      // Then the real terminal event.
      realtimeController.add(
        realtimeMessage(status: 'CANCELLED', cid: testCid),
      );

      final states = await subscription.stream.toList();
      expect(states, hasLength(1));
      expect(states.single, isA<PaymentCancelled>());
    });
  });
}
