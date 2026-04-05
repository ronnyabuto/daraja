import 'dart:convert';

import 'package:daraja/src/client/daraja_client.dart';
import 'package:daraja/src/models/daraja_exception.dart';
import 'package:daraja/src/models/payment_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';

import '../helpers/fixtures.dart';

class _MockHttpClient extends Mock implements http.Client {}

void main() {
  late _MockHttpClient mockHttp;
  late DarajaClient client;

  setUp(() {
    mockHttp = _MockHttpClient();
    client = DarajaClient(testConfig, httpClient: mockHttp);

    registerFallbackValue(Uri.parse('https://example.com'));
  });

  tearDown(() => client.close());

  // Sets up the OAuth mock so tests focused on STK Push don't need to repeat it.
  void stubOauth() {
    when(
      () => mockHttp.get(any(), headers: any(named: 'headers')),
    ).thenAnswer((_) async => oauthSuccess());
  }

  // Captures the body sent to the STK Push endpoint.
  Map<String, dynamic> captureRequestBody() {
    final captured = verify(
      () => mockHttp.post(
        any(),
        headers: any(named: 'headers'),
        body: captureAny(named: 'body'),
      ),
    ).captured;
    return jsonDecode(captured.single as String) as Map<String, dynamic>;
  }

  group('OAuth token fetch', () {
    test('fetches a token and returns it on success', () async {
      stubOauth();
      when(
        () => mockHttp.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => stkPushSuccess());

      await client.initiateStkPush(
        phone: '0712345678',
        amount: 100,
        reference: 'REF',
        description: 'Test',
        userId: testUserId,
      );

      verify(
        () => mockHttp.get(any(), headers: any(named: 'headers')),
      ).called(1);
    });

    test('sends Basic Auth header with base64 encoded credentials', () async {
      final expectedCredentials = base64.encode(
        utf8.encode('${testConfig.consumerKey}:${testConfig.consumerSecret}'),
      );

      when(
        () => mockHttp.get(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async => oauthSuccess());
      when(
        () => mockHttp.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => stkPushSuccess());

      await client.initiateStkPush(
        phone: '0712345678',
        amount: 100,
        reference: 'REF',
        description: 'Test',
        userId: testUserId,
      );

      final captured = verify(
        () => mockHttp.get(any(), headers: captureAny(named: 'headers')),
      ).captured;
      final headers = captured.single as Map<String, String>;
      expect(headers['Authorization'], 'Basic $expectedCredentials');
    });

    test(
      'caches the token — second call does not hit OAuth endpoint',
      () async {
        stubOauth();
        when(
          () => mockHttp.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer((_) async => stkPushSuccess());

        await client.initiateStkPush(
          phone: '0712345678',
          amount: 100,
          reference: 'R',
          description: 'D',
          userId: testUserId,
        );
        await client.initiateStkPush(
          phone: '0712345678',
          amount: 100,
          reference: 'R',
          description: 'D',
          userId: testUserId,
        );

        // Token should be cached — OAuth endpoint called only once.
        verify(
          () => mockHttp.get(any(), headers: any(named: 'headers')),
        ).called(1);
      },
    );

    test('throws DarajaException with statusCode on OAuth failure', () async {
      when(
        () => mockHttp.get(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async => apiError(401, 'Unauthorized'));

      expect(
        () => client.initiateStkPush(
          phone: '0712345678',
          amount: 100,
          reference: 'R',
          description: 'D',
          userId: testUserId,
        ),
        throwsA(
          isA<DarajaException>().having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
    });

    test('throws DarajaAuthError on OAuth 401', () async {
      when(
        () => mockHttp.get(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async => apiError(401, 'Unauthorized'));

      await expectLater(
        client.initiateStkPush(
          phone: '0712345678',
          amount: 100,
          reference: 'R',
          description: 'D',
          userId: testUserId,
        ),
        throwsA(
          isA<DarajaAuthError>().having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
    });

    test('throws DarajaAuthError on OAuth 403', () async {
      when(
        () => mockHttp.get(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async => apiError(403, 'Forbidden'));

      await expectLater(
        client.initiateStkPush(
          phone: '0712345678',
          amount: 100,
          reference: 'R',
          description: 'D',
          userId: testUserId,
        ),
        throwsA(
          isA<DarajaAuthError>().having((e) => e.statusCode, 'statusCode', 403),
        ),
      );
    });

    test('hits the correct sandbox OAuth URL', () async {
      stubOauth();
      when(
        () => mockHttp.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => stkPushSuccess());

      await client.initiateStkPush(
        phone: '0712345678',
        amount: 100,
        reference: 'R',
        description: 'D',
        userId: testUserId,
      );

      final captured = verify(
        () => mockHttp.get(captureAny(), headers: any(named: 'headers')),
      ).captured;
      final uri = captured.single as Uri;
      expect(uri.toString(), contains('sandbox.safaricom.co.ke'));
      expect(uri.toString(), contains('grant_type=client_credentials'));
    });
  });

  group('STK Push — phone normalisation', () {
    Future<void> stubAndVerifyPhone(String input, String expected) async {
      stubOauth();
      when(
        () => mockHttp.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => stkPushSuccess());

      await client.initiateStkPush(
        phone: input,
        amount: 100,
        reference: 'REF',
        description: 'Test',
        userId: testUserId,
      );

      final body = captureRequestBody();
      expect(
        body['PhoneNumber'],
        expected,
        reason: 'Phone "$input" should normalise to "$expected"',
      );
      expect(body['PartyA'], expected);
    }

    test('normalises 07XXXXXXXX format', () async {
      await stubAndVerifyPhone('0712345678', '254712345678');
    });

    test('normalises 01XXXXXXXX format', () async {
      await stubAndVerifyPhone('0112345678', '254112345678');
    });

    test('normalises 7XXXXXXXX (9-digit) format', () async {
      await stubAndVerifyPhone('712345678', '254712345678');
    });

    test('normalises 1XXXXXXXX (9-digit) format', () async {
      await stubAndVerifyPhone('112345678', '254112345678');
    });

    test('normalises +254XXXXXXXXX format', () async {
      await stubAndVerifyPhone('+254712345678', '254712345678');
    });

    test('normalises 254XXXXXXXXX format — pass-through', () async {
      await stubAndVerifyPhone('254712345678', '254712345678');
    });

    test('strips surrounding whitespace before normalising', () async {
      await stubAndVerifyPhone('  0712345678  ', '254712345678');
    });

    test('throws FormatException for unrecognisable phone format', () async {
      // _normalisePhone runs before any network call, so OAuth must never fire.
      await expectLater(
        client.initiateStkPush(
          phone: '12345',
          amount: 100,
          reference: 'REF',
          description: 'Test',
          userId: testUserId,
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('12345'),
          ),
        ),
      );
      verifyNever(() => mockHttp.get(any(), headers: any(named: 'headers')));
    });
  });

  group('STK Push — input validation', () {
    // Validation runs before any network call.

    test('throws ArgumentError for amount of zero', () {
      expect(
        () => client.initiateStkPush(
          phone: '0712345678',
          amount: 0,
          reference: 'REF',
          description: 'Test',
          userId: testUserId,
        ),
        throwsA(isA<ArgumentError>()),
      );
      verifyNever(() => mockHttp.get(any(), headers: any(named: 'headers')));
    });

    test('throws ArgumentError for negative amount', () {
      expect(
        () => client.initiateStkPush(
          phone: '0712345678',
          amount: -50,
          reference: 'REF',
          description: 'Test',
          userId: testUserId,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws ArgumentError when reference exceeds 12 characters', () {
      expect(
        () => client.initiateStkPush(
          phone: '0712345678',
          amount: 100,
          reference: 'ABCDEFGHIJKLM', // 13 chars
          description: 'Test',
          userId: testUserId,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('accepts reference of exactly 12 characters', () async {
      stubOauth();
      when(
        () => mockHttp.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => stkPushSuccess());

      await expectLater(
        client.initiateStkPush(
          phone: '0712345678',
          amount: 100,
          reference: 'ABCDEFGHIJKL', // exactly 12 chars
          description: 'Test',
          userId: testUserId,
        ),
        completes,
      );
    });

    test('throws ArgumentError when description exceeds 13 characters', () {
      expect(
        () => client.initiateStkPush(
          phone: '0712345678',
          amount: 100,
          reference: 'REF',
          description: 'ABCDEFGHIJKLMN', // 14 chars
          userId: testUserId,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('accepts description of exactly 13 characters', () async {
      stubOauth();
      when(
        () => mockHttp.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => stkPushSuccess());

      await expectLater(
        client.initiateStkPush(
          phone: '0712345678',
          amount: 100,
          reference: 'REF',
          description: 'ABCDEFGHIJKLM', // exactly 13 chars
          userId: testUserId,
        ),
        completes,
      );
    });
  });

  group('STK Push — request body', () {
    setUp(stubOauth);

    test(
      'sends correct password: base64(shortcode + passkey + timestamp)',
      () async {
        when(
          () => mockHttp.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer((_) async => stkPushSuccess());

        await client.initiateStkPush(
          phone: '0712345678',
          amount: 100,
          reference: 'REF',
          description: 'Test',
          userId: testUserId,
        );

        final body = captureRequestBody();
        final timestamp = body['Timestamp'] as String;
        final expectedRaw =
            '${testConfig.shortcode}${testConfig.passkey}$timestamp';
        final expectedPassword = base64.encode(utf8.encode(expectedRaw));

        expect(body['Password'], expectedPassword);
      },
    );

    test('timestamp is 14 digits in YYYYMMDDHHmmss format', () async {
      when(
        () => mockHttp.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => stkPushSuccess());

      await client.initiateStkPush(
        phone: '0712345678',
        amount: 100,
        reference: 'REF',
        description: 'Test',
        userId: testUserId,
      );

      final body = captureRequestBody();
      final timestamp = body['Timestamp'] as String;

      expect(timestamp, matches(RegExp(r'^\d{14}$')));

      // Parse and verify it represents a plausible EAT datetime (UTC+3).
      final year = int.parse(timestamp.substring(0, 4));
      final month = int.parse(timestamp.substring(4, 6));
      final day = int.parse(timestamp.substring(6, 8));
      final hour = int.parse(timestamp.substring(8, 10));

      expect(year, greaterThanOrEqualTo(2026));
      expect(month, inInclusiveRange(1, 12));
      expect(day, inInclusiveRange(1, 31));
      // EAT is UTC+3 — hour must be 0-23.
      expect(hour, inInclusiveRange(0, 23));
    });

    test('timestamp and password share the same datetime value', () async {
      when(
        () => mockHttp.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => stkPushSuccess());

      await client.initiateStkPush(
        phone: '0712345678',
        amount: 100,
        reference: 'REF',
        description: 'Test',
        userId: testUserId,
      );

      final body = captureRequestBody();
      final timestamp = body['Timestamp'] as String;
      final password = body['Password'] as String;

      final decoded = utf8.decode(base64.decode(password));
      expect(decoded, endsWith(timestamp));
    });

    test('constructs CallBackURL with domain, path and userId', () async {
      when(
        () => mockHttp.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => stkPushSuccess());

      await client.initiateStkPush(
        phone: '0712345678',
        amount: 100,
        reference: 'REF',
        description: 'Test',
        userId: 'user_xyz',
      );

      final body = captureRequestBody();
      expect(
        body['CallBackURL'],
        '${testConfig.callbackDomain}/callback?uid=user_xyz',
      );
    });

    test('sends correct TransactionType', () async {
      when(
        () => mockHttp.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => stkPushSuccess());

      await client.initiateStkPush(
        phone: '0712345678',
        amount: 500,
        reference: 'REF',
        description: 'Test',
        userId: testUserId,
      );

      final body = captureRequestBody();
      expect(body['TransactionType'], 'CustomerPayBillOnline');
      expect(body['Amount'], 500);
      expect(body['BusinessShortCode'], testConfig.shortcode);
    });
  });

  group('STK Push — response handling', () {
    setUp(stubOauth);

    test('returns CheckoutRequestID on success', () async {
      when(
        () => mockHttp.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => stkPushSuccess('ws_CO_unique_123'));

      final cid = await client.initiateStkPush(
        phone: '0712345678',
        amount: 100,
        reference: 'REF',
        description: 'Test',
        userId: testUserId,
      );

      expect(cid, 'ws_CO_unique_123');
    });

    test('throws DarajaException with statusCode on non-200 response', () {
      when(
        () => mockHttp.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => apiError(500));

      expect(
        () => client.initiateStkPush(
          phone: '0712345678',
          amount: 100,
          reference: 'REF',
          description: 'Test',
          userId: testUserId,
        ),
        throwsA(
          isA<DarajaException>().having((e) => e.statusCode, 'statusCode', 500),
        ),
      );
    });

    test('throws DarajaException when ResponseCode is not "0"', () {
      when(
        () => mockHttp.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => stkPushRejected());

      expect(
        () => client.initiateStkPush(
          phone: '0712345678',
          amount: 100,
          reference: 'REF',
          description: 'Test',
          userId: testUserId,
        ),
        throwsA(isA<DarajaException>()),
      );
    });

    test(
      'throws StkPushRejectedError with responseCode when ResponseCode is non-zero',
      () async {
        when(
          () => mockHttp.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer((_) async => stkPushRejected());

        await expectLater(
          client.initiateStkPush(
            phone: '0712345678',
            amount: 100,
            reference: 'REF',
            description: 'Test',
            userId: testUserId,
          ),
          throwsA(
            isA<StkPushRejectedError>().having(
              (e) => e.responseCode,
              'responseCode',
              '1',
            ),
          ),
        );
      },
    );

    test(
      'throws StkPushRejectedError with responseCode 1025 when transaction in progress',
      () async {
        when(
          () => mockHttp.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer((_) async => stkPushTransactionInProgress());

        await expectLater(
          client.initiateStkPush(
            phone: '0712345678',
            amount: 100,
            reference: 'REF',
            description: 'Test',
            userId: testUserId,
          ),
          throwsA(
            isA<StkPushRejectedError>().having(
              (e) => e.responseCode,
              'responseCode',
              '1025',
            ),
          ),
        );
      },
    );
  });

  group('STK Query', () {
    setUp(stubOauth);

    test(
      'returns PaymentResult with isPending=true when still processing',
      () async {
        when(
          () => mockHttp.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer((_) async => stkQueryPending());

        final result = await client.queryStkStatus(testCid);

        expect(result, isA<PaymentResult>());
        expect(result.checkoutRequestId, testCid);
        expect(result.isPending, isTrue);
        expect(result.resultCode, 17);
      },
    );

    test(
      'returns PaymentResult with isSuccess=true on completed payment',
      () async {
        when(
          () => mockHttp.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer((_) async => stkQuerySuccess());

        final result = await client.queryStkStatus(testCid);

        expect(result.isSuccess, isTrue);
        expect(result.resultCode, 0);
      },
    );

    test(
      'returns PaymentResult with isCancelled=true on user cancellation',
      () async {
        when(
          () => mockHttp.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer((_) async => stkQueryCancelled());

        final result = await client.queryStkStatus(testCid);

        expect(result.isCancelled, isTrue);
        expect(result.resultCode, 1032);
      },
    );

    test('throws DarajaException with statusCode on non-200 response', () {
      when(
        () => mockHttp.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => apiError(503));

      expect(
        () => client.queryStkStatus(testCid),
        throwsA(
          isA<DarajaException>().having((e) => e.statusCode, 'statusCode', 503),
        ),
      );
    });

    test('sends CheckoutRequestID in request body', () async {
      when(
        () => mockHttp.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => stkQuerySuccess());

      await client.queryStkStatus('ws_CO_specific_99');

      final body = captureRequestBody();
      expect(body['CheckoutRequestID'], 'ws_CO_specific_99');
    });
  });
}
