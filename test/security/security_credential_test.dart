import 'dart:convert';

import 'package:daraja/src/security/security_credential.dart';
import 'package:encrypt/encrypt.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/asymmetric/api.dart' show RSAPrivateKey;

// 1024-bit test RSA key pair — test only, never used in production.
// Generated with: openssl genrsa -traditional 1024
const _testPublicKeyPem = '''
-----BEGIN PUBLIC KEY-----
MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQC56HcbsEF07/D0Rwv15tJzHgWR
E2s+2+TyHcQDVb4nBzpT/uLdhe9W4w9v1wJPV5xqHeb9MyHwMIeNZ51vi7Wmw5Q0
UF7eoQ5XSrMtmjUneWGxnEo9m1qb6SkxFSU1ocT9igJ6SNBcpRazkZdKS6mZCJXK
luM0A4HVZlG3Bf18BQIDAQAB
-----END PUBLIC KEY-----''';

const _testPrivateKeyPem = '''
-----BEGIN RSA PRIVATE KEY-----
MIICXgIBAAKBgQC56HcbsEF07/D0Rwv15tJzHgWRE2s+2+TyHcQDVb4nBzpT/uLd
he9W4w9v1wJPV5xqHeb9MyHwMIeNZ51vi7Wmw5Q0UF7eoQ5XSrMtmjUneWGxnEo9
m1qb6SkxFSU1ocT9igJ6SNBcpRazkZdKS6mZCJXKluM0A4HVZlG3Bf18BQIDAQAB
AoGBAJDt5CUGxBC4mVymInHiL0AlMGvH+rx3SsVhZRTAfEwKu3MN6qiNqGdQ/hDP
SnK2Ny8W/qN3gEayXopjM33pKYNzDVXO/eHrTjcDwNG3adYbg+KelKMGeIaDyeNO
YAem3yCUXUWHkIbIO/sVkHuEyUJs2t6S6CiQ2i/HrvMgZc/BAkEA3vecVZDA1EU/
S8O6xA2mKFStDUOHT7Gkm1zYIdLyj1EjY1DinbAk3ozo6t13RVCEu9vdTRgDDp5H
ydfPOyXLkQJBANVzU5ZkllIRj7iL2/WMYyaPeEhhKWAAJY5Ik5LvOJSKZJQRO0mg
xRKSQMZnzeXFDE/oFUEkQixWkeLP8c6TZzUCQHPttGg80jXMJ2PiScpD+n9/v1Zl
JQaHq7ln5ax4fMuNeWPbG2i3vAPGqhfrvGbavZjbcU3zTSudml/VCJeNSDECQQCm
G4aL/iFBIqt+yVBWiXbLllDbuskRDWwsiuxVJ1cXuY9F7xb9WGCk8C36eOOxkKPh
N1H7DLV2fbQwFvUtdmaVAkEAm4U33ym3y9KNOGxbJCchsRJR1FZreVvKo4CETcZ2
ESfGAYAdjVCGtA94tVPhNGv8AdNR/I6ZTQnFmr9bqERR/A==
-----END RSA PRIVATE KEY-----''';

void main() {
  group('SecurityCredential.generate()', () {
    test('returns non-empty Base64 string', () {
      final result = SecurityCredential.generate(
        initiatorPassword: 'TestPassword123',
        certificate: _testPublicKeyPem,
      );

      expect(result, isNotEmpty);
      // Must be valid Base64.
      expect(() => base64.decode(result), returnsNormally);
    });

    test('ciphertext decrypts to the original password', () {
      const password = 'Safaricom999!*!';
      final credential = SecurityCredential.generate(
        initiatorPassword: password,
        certificate: _testPublicKeyPem,
      );

      final privateKey =
          RSAKeyParser().parse(_testPrivateKeyPem) as RSAPrivateKey;
      final decrypter = Encrypter(
        RSA(privateKey: privateKey, encoding: RSAEncoding.PKCS1),
      );
      final decrypted = decrypter.decrypt64(credential);

      expect(decrypted, password);
    });

    test(
      'produces different ciphertext each call (PKCS#1 v1.5 randomness)',
      () {
        const password = 'Safaricom999!*!';
        final a = SecurityCredential.generate(
          initiatorPassword: password,
          certificate: _testPublicKeyPem,
        );
        final b = SecurityCredential.generate(
          initiatorPassword: password,
          certificate: _testPublicKeyPem,
        );

        // PKCS#1 v1.5 padding is randomised — two encryptions of the same
        // plaintext must not produce identical ciphertext.
        expect(a, isNot(equals(b)));
      },
    );

    test('throws ArgumentError for an invalid certificate PEM', () {
      expect(
        () => SecurityCredential.generate(
          initiatorPassword: 'password',
          certificate: 'not-a-pem',
        ),
        throwsArgumentError,
      );
    });

    test(
      'throws ArgumentError for a certificate that is not an RSA public key',
      () {
        // Valid PEM structure but wrong key type header — RSAKeyParser will fail.
        const notRsaPublicKey = '''
-----BEGIN CERTIFICATE-----
MIICpDCCAYwCCQDU+pQ4pHgSpDANBgkqhkiG9w0BAQsFADAUMRIwEAYDVQQDDAls
-----END CERTIFICATE-----''';

        expect(
          () => SecurityCredential.generate(
            initiatorPassword: 'password',
            certificate: notRsaPublicKey,
          ),
          throwsArgumentError,
        );
      },
    );
  });
}
