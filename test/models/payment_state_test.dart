import 'package:daraja/src/models/payment_state.dart';
import 'package:flutter_test/flutter_test.dart';

PaymentFailed _failed(int code) => PaymentFailed(
  checkoutRequestId: 'ws_CO_test',
  resultCode: code,
  message: 'desc',
);

void main() {
  group('PaymentFailed', () {
    group('isInsufficientFunds', () {
      test('true only for resultCode 1', () {
        expect(_failed(1).isInsufficientFunds, isTrue);
      });

      test('false for all other codes', () {
        for (final code in [0, 2001, 1001, 1031, 9999]) {
          expect(
            _failed(code).isInsufficientFunds,
            isFalse,
            reason: 'expected isInsufficientFunds=false for code $code',
          );
        }
      });
    });

    group('isWrongPin', () {
      test('true only for resultCode 2001', () {
        expect(_failed(2001).isWrongPin, isTrue);
      });

      test('false for all other codes', () {
        for (final code in [0, 1, 1001, 1031, 9999]) {
          expect(
            _failed(code).isWrongPin,
            isFalse,
            reason: 'expected isWrongPin=false for code $code',
          );
        }
      });
    });

    group('isSubscriberLocked', () {
      test('true only for resultCode 1001', () {
        expect(_failed(1001).isSubscriberLocked, isTrue);
      });

      test('false for all other codes', () {
        for (final code in [0, 1, 2001, 1031, 9999]) {
          expect(
            _failed(code).isSubscriberLocked,
            isFalse,
            reason: 'expected isSubscriberLocked=false for code $code',
          );
        }
      });
    });

    test('at most one flag is true for any given result code', () {
      for (final code in [0, 1, 1001, 2001, 1031, 9999]) {
        final f = _failed(code);
        final trueCount = [
          f.isInsufficientFunds,
          f.isWrongPin,
          f.isSubscriberLocked,
        ].where((b) => b).length;
        expect(
          trueCount,
          lessThanOrEqualTo(1),
          reason: 'multiple flags true for code $code',
        );
      }
    });

    test('all flags false for unrecognised failure code', () {
      final f = _failed(1031);
      expect(f.isInsufficientFunds, isFalse);
      expect(f.isWrongPin, isFalse);
      expect(f.isSubscriberLocked, isFalse);
    });
  });
}
