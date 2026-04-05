import 'package:encrypt/encrypt.dart';
import 'package:pointycastle/asymmetric/api.dart' show RSAPublicKey;

/// Generates the [SecurityCredential] required by Safaricom B2C, Account
/// Balance, Transaction Status, and Reversal APIs.
///
/// Safaricom requires the [initiatorPassword] to be RSA-encrypted (PKCS#1
/// v1.5) using Safaricom's public key, then Base64-encoded.
///
/// The [certificate] parameter must be a PKCS#8 PEM public key string
/// (`-----BEGIN PUBLIC KEY-----`), NOT the raw `.cer` X.509 certificate file.
/// Extract it first with:
/// ```
/// openssl x509 -in SandboxCertificate.cer -inform DER -pubkey -noout
/// ```
///
/// Safaricom provides separate certificates for sandbox and production.
/// Store the extracted PEM in your app configuration or backend — never
/// commit plaintext certificates to public repositories.
///
/// Example:
/// ```dart
/// const pem = '-----BEGIN PUBLIC KEY-----\n...\n-----END PUBLIC KEY-----';
/// final credential = SecurityCredential.generate(
///   initiatorPassword: 'Safaricom999!*!',
///   certificate: pem,
/// );
/// ```
abstract final class SecurityCredential {
  const SecurityCredential._();

  /// Encrypts [initiatorPassword] with [certificate] and returns the
  /// Base64-encoded ciphertext suitable for use as `SecurityCredential` in
  /// Safaricom API requests.
  ///
  /// Throws [ArgumentError] if [certificate] is not a valid PKCS#8 RSA public
  /// key PEM string.
  static String generate({
    required String initiatorPassword,
    required String certificate,
  }) {
    final RSAPublicKey publicKey;
    try {
      publicKey = RSAKeyParser().parse(certificate) as RSAPublicKey;
    } catch (e) {
      throw ArgumentError.value(
        certificate,
        'certificate',
        'Invalid RSA public key PEM. '
            'Extract it from the Safaricom .cer file with: '
            'openssl x509 -in cert.cer -inform DER -pubkey -noout',
      );
    }

    final encrypter = Encrypter(
      RSA(publicKey: publicKey, encoding: RSAEncoding.PKCS1),
    );
    return encrypter.encrypt(initiatorPassword).base64;
  }
}
