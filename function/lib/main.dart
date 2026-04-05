import 'dart:convert';
import 'dart:io';

import 'package:dart_appwrite/dart_appwrite.dart';

Future<dynamic> main(final context) async {
  Map<String, dynamic> payload;
  try {
    payload =
        jsonDecode(context.req.bodyText as String) as Map<String, dynamic>;
  } catch (_) {
    context.error('Unparseable callback body: ${context.req.bodyText}');
    return context.res.json({
      'ResultCode': 1,
      'ResultDesc': 'Invalid payload',
    }, 400);
  }

  final stkCallback = payload['Body']?['stkCallback'] as Map<String, dynamic>?;
  if (stkCallback == null) {
    context.error('Missing Body.stkCallback');
    return context.res.json({
      'ResultCode': 1,
      'ResultDesc': 'Malformed payload',
    }, 400);
  }

  final checkoutRequestId = stkCallback['CheckoutRequestID'] as String;
  final resultCode = stkCallback['ResultCode'] as int;
  final resultDesc = stkCallback['ResultDesc'] as String? ?? '';
  final isSuccess = resultCode == 0;

  final userId = context.req.query['uid'] as String?;

  String? receipt;
  int? amount;
  String? mpesaTimestamp;
  if (isSuccess) {
    final items = (stkCallback['CallbackMetadata']?['Item'] as List?)
        ?.cast<Map<String, dynamic>>();
    receipt =
        items?.firstWhere(
              (i) => i['Name'] == 'MpesaReceiptNumber',
              orElse: () => {'Value': null},
            )['Value']
            as String?;
    amount =
        (items?.firstWhere(
                  (i) => i['Name'] == 'Amount',
                  orElse: () => {'Value': null},
                )['Value']
                as num?)
            ?.toInt();

    // TransactionDate is returned as an integer in YYYYMMDDHHmmss format (EAT).
    // PhoneNumber is intentionally not extracted — Safaricom now masks it
    // (e.g. "0722000***") as of March 2026. Use userId from the query param
    // for user lookup instead.
    final txDateRaw = items?.firstWhere(
      (i) => i['Name'] == 'TransactionDate',
      orElse: () => {'Value': null},
    )['Value'];
    if (txDateRaw != null) {
      mpesaTimestamp = _parseTransactionDate(txDateRaw.toString());
    }
  }

  final client = Client()
    ..setEndpoint(Platform.environment['APPWRITE_FUNCTION_API_ENDPOINT']!)
    ..setProject(Platform.environment['APPWRITE_FUNCTION_PROJECT_ID']!)
    ..setKey(Platform.environment['APPWRITE_API_KEY']!);

  final databases = Databases(client);

  final permissions = (userId != null && userId.isNotEmpty)
      ? [Permission.read(Role.user(userId))]
      : [Permission.read(Role.any())];

  try {
    await databases.createDocument(
      databaseId: Platform.environment['DARAJA_DATABASE_ID']!,
      collectionId: Platform.environment['DARAJA_COLLECTION_ID']!,
      documentId: checkoutRequestId,
      data: {
        'checkoutRequestId': checkoutRequestId,
        'status': isSuccess ? 'SUCCESS' : _mapStatus(resultCode),
        'resultCode': resultCode,
        'receipt': receipt,
        'amount': amount,
        'failureReason': isSuccess ? null : resultDesc,
        'mpesaTimestamp': mpesaTimestamp,
        'settledAt': DateTime.now().toUtc().toIso8601String(),
      },
      permissions: permissions,
    );
    context.log(
      'Processed $checkoutRequestId → ${isSuccess ? 'SUCCESS' : 'resultCode=$resultCode'}',
    );
  } on AppwriteException catch (e) {
    if (e.code == 409) {
      context.log('Duplicate callback for $checkoutRequestId — ignored');
    } else {
      context.error('DB write failed for $checkoutRequestId: $e');
    }
  } catch (e) {
    context.error('Unexpected error for $checkoutRequestId: $e');
  }

  return context.res.json({'ResultCode': 0, 'ResultDesc': 'Accepted'});
}

String _mapStatus(int code) => switch (code) {
  1032 => 'CANCELLED',
  1037 => 'TIMEOUT',
  _ => 'FAILED',
};

/// Parse a Safaricom TransactionDate integer (YYYYMMDDHHmmss, EAT) to ISO 8601.
/// Returns null if the value is malformed.
String? _parseTransactionDate(String raw) {
  if (raw.length != 14) return null;
  try {
    final year = int.parse(raw.substring(0, 4));
    final month = int.parse(raw.substring(4, 6));
    final day = int.parse(raw.substring(6, 8));
    final hour = int.parse(raw.substring(8, 10));
    final minute = int.parse(raw.substring(10, 12));
    final second = int.parse(raw.substring(12, 14));
    // EAT is UTC+3. Store as UTC.
    return DateTime.utc(
      year,
      month,
      day,
      hour,
      minute,
      second,
    ).subtract(const Duration(hours: 3)).toIso8601String();
  } catch (_) {
    return null;
  }
}
