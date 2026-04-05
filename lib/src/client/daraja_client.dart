import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/daraja_config.dart';
import '../models/daraja_exception.dart';
import '../models/payment_result.dart';
import 'token_cache.dart';

class DarajaClient {
  DarajaClient(this._config, {http.Client? httpClient})
    : _http = httpClient ?? http.Client(),
      _cache = TokenCache();

  final DarajaConfig _config;
  final http.Client _http;
  final TokenCache _cache;

  Future<String> initiateStkPush({
    required String phone,
    required int amount,
    required String reference,
    required String description,
    required String userId,
  }) async {
    _validate(amount: amount, reference: reference, description: description);
    final normalised = _normalisePhone(
      phone,
    ); // Validate before any network call.

    final token = await _getToken();
    final timestamp = _eatTimestamp();

    final response = await _http.post(
      Uri.parse('${_config.baseUrl}/mpesa/stkpush/v1/processrequest'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'BusinessShortCode': _config.shortcode,
        'Password': _password(timestamp),
        'Timestamp': timestamp,
        'TransactionType': 'CustomerPayBillOnline',
        'Amount': amount,
        'PartyA': normalised,
        'PartyB': _config.shortcode,
        'PhoneNumber': normalised,
        'CallBackURL': '${_config.callbackDomain}/callback?uid=$userId',
        'AccountReference': reference,
        'TransactionDesc': description,
      }),
    );

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200) {
      throw DarajaException(
        body['errorMessage'] as String? ?? 'STK Push failed',
        statusCode: response.statusCode,
      );
    }

    if (body['ResponseCode'] != '0') {
      throw StkPushRejectedError(
        body['ResponseDescription'] as String? ?? 'STK Push rejected',
        responseCode: body['ResponseCode'] as String,
      );
    }

    return body['CheckoutRequestID'] as String;
  }

  Future<PaymentResult> queryStkStatus(String checkoutRequestId) async {
    final token = await _getToken();
    final timestamp = _eatTimestamp();

    final response = await _http.post(
      Uri.parse('${_config.baseUrl}/mpesa/stkpushquery/v1/query'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'BusinessShortCode': _config.shortcode,
        'Password': _password(timestamp),
        'Timestamp': timestamp,
        'CheckoutRequestID': checkoutRequestId,
      }),
    );

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200) {
      throw DarajaException(
        body['errorMessage'] as String? ?? 'STK Query failed',
        statusCode: response.statusCode,
      );
    }

    return PaymentResult(
      checkoutRequestId: checkoutRequestId,
      resultCode: int.parse(body['ResultCode'] as String),
      resultDesc: body['ResultDesc'] as String? ?? '',
    );
  }

  Future<String> _getToken() async {
    final cached = _cache.token;
    if (cached != null) return cached;

    final credentials = base64.encode(
      utf8.encode('${_config.consumerKey}:${_config.consumerSecret}'),
    );

    final response = await _http.get(
      Uri.parse(
        '${_config.baseUrl}/oauth/v1/generate?grant_type=client_credentials',
      ),
      headers: {'Authorization': 'Basic $credentials'},
    );

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw DarajaAuthError(
        'OAuth failed: check consumerKey and consumerSecret',
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode != 200) {
      throw DarajaException('OAuth failed', statusCode: response.statusCode);
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final token = body['access_token'] as String;
    final expiresIn = int.parse(body['expires_in'] as String);

    _cache.store(token, expiresIn);
    return token;
  }

  String _password(String timestamp) {
    final raw = '${_config.shortcode}${_config.passkey}$timestamp';
    return base64.encode(utf8.encode(raw));
  }

  String _eatTimestamp() {
    final eat = DateTime.now().toUtc().add(const Duration(hours: 3));
    return '${eat.year}'
        '${eat.month.toString().padLeft(2, '0')}'
        '${eat.day.toString().padLeft(2, '0')}'
        '${eat.hour.toString().padLeft(2, '0')}'
        '${eat.minute.toString().padLeft(2, '0')}'
        '${eat.second.toString().padLeft(2, '0')}';
  }

  static String _normalisePhone(String raw) {
    final phone = raw.trim().replaceAll(RegExp(r'\s+'), '');

    if (phone.startsWith('+254') && phone.length == 13) {
      return phone.substring(1);
    }
    if (phone.startsWith('254') && phone.length == 12) {
      return phone;
    }
    if ((phone.startsWith('07') || phone.startsWith('01')) &&
        phone.length == 10) {
      return '254${phone.substring(1)}';
    }
    if ((phone.startsWith('7') || phone.startsWith('1')) && phone.length == 9) {
      return '254$phone';
    }

    throw FormatException('Unrecognised phone format: $raw');
  }

  static void _validate({
    required int amount,
    required String reference,
    required String description,
  }) {
    if (amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'must be a positive integer');
    }
    if (reference.length > 12) {
      throw ArgumentError.value(
        reference,
        'reference',
        'exceeds 12 character limit',
      );
    }
    if (description.length > 13) {
      throw ArgumentError.value(
        description,
        'description',
        'exceeds 13 character limit',
      );
    }
  }

  void close() => _http.close();
}
