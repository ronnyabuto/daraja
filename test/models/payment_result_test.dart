import 'package:daraja/src/models/payment_result.dart';
import 'package:flutter_test/flutter_test.dart';

PaymentResult _result(int code) => PaymentResult(
      checkoutRequestId: 'ws_CO_test',
      resultCode: code,
      resultDesc: 'desc',
    );

void main() {
  group('PaymentResult', () {
    group('isSuccess', () {
      test('true only for resultCode 0', () {
        expect(_result(0).isSuccess, isTrue);
      });

      test('false for all non-zero codes', () {
        for (final code in [1, 17, 1031, 1032, 1037, 9999]) {
          expect(_result(code).isSuccess, isFalse,
              reason: 'expected isSuccess=false for code $code');
        }
      });
    });

    group('isCancelled', () {
      test('true only for resultCode 1032', () {
        expect(_result(1032).isCancelled, isTrue);
      });

      test('false for all other codes', () {
        for (final code in [0, 1, 17, 1031, 1037]) {
          expect(_result(code).isCancelled, isFalse,
              reason: 'expected isCancelled=false for code $code');
        }
      });
    });

    group('isTimeout', () {
      test('true only for resultCode 1037', () {
        expect(_result(1037).isTimeout, isTrue);
      });

      test('false for all other codes', () {
        for (final code in [0, 1, 17, 1031, 1032]) {
          expect(_result(code).isTimeout, isFalse,
              reason: 'expected isTimeout=false for code $code');
        }
      });
    });

    group('isPending', () {
      test('true only for resultCode 17', () {
        expect(_result(17).isPending, isTrue);
      });

      test('false for all other codes', () {
        for (final code in [0, 1, 1031, 1032, 1037]) {
          expect(_result(code).isPending, isFalse,
              reason: 'expected isPending=false for code $code');
        }
      });
    });

    test('at most one flag is true for any given result code', () {
      final codes = [0, 17, 1031, 1032, 1037, 9999];
      for (final code in codes) {
        final r = _result(code);
        final trueCount = [r.isSuccess, r.isCancelled, r.isTimeout, r.isPending]
            .where((b) => b)
            .length;
        expect(trueCount, lessThanOrEqualTo(1),
            reason: 'multiple flags true for code $code');
      }
    });

    test('all flags false for unrecognised failure codes', () {
      // 1031 = insufficient funds — a real failure with no specific flag
      final r = _result(1031);
      expect(r.isSuccess, isFalse);
      expect(r.isCancelled, isFalse);
      expect(r.isTimeout, isFalse);
      expect(r.isPending, isFalse);
    });

    test('preserves checkoutRequestId and resultDesc', () {
      final r = PaymentResult(
        checkoutRequestId: 'ws_CO_specific',
        resultCode: 0,
        resultDesc: 'The service request is processed successfully.',
      );
      expect(r.checkoutRequestId, 'ws_CO_specific');
      expect(r.resultDesc, 'The service request is processed successfully.');
    });
  });
}
