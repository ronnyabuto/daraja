import 'package:daraja/src/client/token_cache.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TokenCache', () {
    late TokenCache cache;

    setUp(() => cache = TokenCache());

    test('returns null before any token is stored', () {
      expect(cache.token, isNull);
    });

    test('returns the stored token immediately after store', () {
      cache.store('access_token_abc', 3600);
      expect(cache.token, 'access_token_abc');
    });

    test('stores the latest token when called multiple times', () {
      cache.store('first', 3600);
      cache.store('second', 3600);
      expect(cache.token, 'second');
    });

    test('applies a 60-second buffer — expires before the actual token TTL', () {
      fakeAsync((fake) {
        cache.store('tok', 3600);

        // At T+3539s: effective expiry is at T+3540s (3600-60), still valid.
        fake.elapse(const Duration(seconds: 3539));
        expect(cache.token, 'tok');

        // At T+3541s: past effective expiry.
        fake.elapse(const Duration(seconds: 2));
        expect(cache.token, isNull);
      });
    });

    test('a token stored with expiresInSeconds equal to buffer expires immediately', () {
      fakeAsync((fake) {
        // effective TTL = 60 - 60 = 0 seconds
        cache.store('tok', 60);
        fake.elapse(const Duration(milliseconds: 1));
        expect(cache.token, isNull);
      });
    });

    test('a token stored with expiresInSeconds less than buffer is already expired', () {
      fakeAsync((fake) {
        // effective TTL = 30 - 60 = -30 seconds (expiresAt already in the past)
        cache.store('tok', 30);
        fake.elapse(Duration.zero);
        expect(cache.token, isNull);
      });
    });

    test('auto-invalidates internal state on the first expired read', () {
      fakeAsync((fake) {
        cache.store('tok', 61); // effective TTL = 1s
        fake.elapse(const Duration(seconds: 2));

        expect(cache.token, isNull); // expired — clears state
        expect(cache.token, isNull); // idempotent — no crash on second call
      });
    });

    test('accepts a fresh token after the previous one expires', () {
      fakeAsync((fake) {
        cache.store('first', 61);
        fake.elapse(const Duration(seconds: 2));
        expect(cache.token, isNull);

        cache.store('second', 3600);
        expect(cache.token, 'second');
      });
    });
  });
}
