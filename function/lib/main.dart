import 'dart:convert';
import 'dart:io';

import 'package:dart_appwrite/dart_appwrite.dart';

Future<dynamic> main(final context) async {
  final path = context.req.path as String? ?? '/callback';

  if (path == '/b2c/result' || path == '/b2c/timeout') {
    return _handleB2c(context, isTimeout: path == '/b2c/timeout');
  }

  return _handleStkCallback(context);
}

// ---------------------------------------------------------------------------
// STK Push callback
// ---------------------------------------------------------------------------

Future<dynamic> _handleStkCallback(final context) async {
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
      mpesaTimestamp = _parseEatTimestamp(txDateRaw.toString());
    }
  }

  final client = _appwriteClient();
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
        'status': isSuccess ? 'SUCCESS' : _mapStkStatus(resultCode),
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
      'STK $checkoutRequestId → ${isSuccess ? 'SUCCESS' : 'resultCode=$resultCode'}',
    );
  } on AppwriteException catch (e) {
    if (e.code == 409) {
      context.log('Duplicate STK callback for $checkoutRequestId — ignored');
    } else {
      context.error('DB write failed for $checkoutRequestId: $e');
    }
  } catch (e) {
    context.error('Unexpected error for $checkoutRequestId: $e');
  }

  return context.res.json({'ResultCode': 0, 'ResultDesc': 'Accepted'});
}

// ---------------------------------------------------------------------------
// B2C result and queue-timeout callbacks
// ---------------------------------------------------------------------------

Future<dynamic> _handleB2c(final context, {required bool isTimeout}) async {
  Map<String, dynamic> payload;
  try {
    payload =
        jsonDecode(context.req.bodyText as String) as Map<String, dynamic>;
  } catch (_) {
    context.error('Unparseable B2C callback body: ${context.req.bodyText}');
    return context.res.json({
      'ResultCode': 1,
      'ResultDesc': 'Invalid payload',
    }, 400);
  }

  final result = payload['Result'] as Map<String, dynamic>?;
  if (result == null) {
    context.error('Missing Result in B2C callback');
    return context.res.json({
      'ResultCode': 1,
      'ResultDesc': 'Malformed payload',
    }, 400);
  }

  final originatorConversationId =
      result['OriginatorConversationID'] as String?;
  if (originatorConversationId == null || originatorConversationId.isEmpty) {
    context.error('Missing OriginatorConversationID in B2C callback');
    return context.res.json({
      'ResultCode': 1,
      'ResultDesc': 'Malformed payload',
    }, 400);
  }

  final conversationId = result['ConversationID'] as String? ?? '';
  final resultCode = result['ResultCode'] as int? ?? -1;
  final resultDesc = result['ResultDesc'] as String? ?? '';
  final userId = context.req.query['uid'] as String?;

  final String status;
  String? receipt;
  int? amount;
  String? receiverName;
  String? mpesaTimestamp;

  if (isTimeout) {
    status = 'TIMEOUT';
  } else if (resultCode == 0) {
    status = 'SUCCESS';

    // Parse ResultParameters.ResultParameter array.
    final params = (result['ResultParameters']?['ResultParameter'] as List?)
        ?.cast<Map<String, dynamic>>();

    receipt =
        params?.firstWhere(
              (p) => p['Key'] == 'TransactionReceipt',
              orElse: () => {'Value': null},
            )['Value']
            as String?;

    amount =
        (params?.firstWhere(
                  (p) => p['Key'] == 'TransactionAmount',
                  orElse: () => {'Value': null},
                )['Value']
                as num?)
            ?.toInt();

    receiverName =
        params?.firstWhere(
              (p) => p['Key'] == 'ReceiverPartyPublicName',
              orElse: () => {'Value': null},
            )['Value']
            as String?;

    // B2C timestamp format: "DD.MM.YYYY HH:mm:ss" (EAT).
    final rawTs =
        params?.firstWhere(
              (p) => p['Key'] == 'TransactionCompletedDateTime',
              orElse: () => {'Value': null},
            )['Value']
            as String?;
    if (rawTs != null) {
      mpesaTimestamp = _parseB2cTimestamp(rawTs);
    }
  } else {
    status = 'FAILED';
  }

  final client = _appwriteClient();
  final databases = Databases(client);

  final permissions = (userId != null && userId.isNotEmpty)
      ? [Permission.read(Role.user(userId))]
      : [Permission.read(Role.any())];

  try {
    await databases.createDocument(
      databaseId: Platform.environment['DARAJA_DATABASE_ID']!,
      collectionId: Platform.environment['DARAJA_B2C_COLLECTION_ID']!,
      documentId: originatorConversationId,
      data: {
        'originatorConversationId': originatorConversationId,
        'conversationId': conversationId,
        'status': status,
        'resultCode': resultCode,
        'receipt': receipt,
        'amount': amount,
        'receiverName': receiverName,
        'failureReason': status == 'SUCCESS' ? null : resultDesc,
        'mpesaTimestamp': mpesaTimestamp,
        'settledAt': DateTime.now().toUtc().toIso8601String(),
      },
      permissions: permissions,
    );
    context.log('B2C $originatorConversationId → $status');
  } on AppwriteException catch (e) {
    if (e.code == 409) {
      context.log(
        'Duplicate B2C callback for $originatorConversationId — ignored',
      );
    } else {
      context.error('DB write failed for B2C $originatorConversationId: $e');
    }
  } catch (e) {
    context.error('Unexpected B2C error for $originatorConversationId: $e');
  }

  return context.res.json({'ResultCode': 0, 'ResultDesc': 'Accepted'});
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Client _appwriteClient() => Client()
  ..setEndpoint(Platform.environment['APPWRITE_FUNCTION_API_ENDPOINT']!)
  ..setProject(Platform.environment['APPWRITE_FUNCTION_PROJECT_ID']!)
  ..setKey(Platform.environment['APPWRITE_API_KEY']!);

String _mapStkStatus(int code) => switch (code) {
  1032 => 'CANCELLED',
  1037 => 'TIMEOUT',
  _ => 'FAILED',
};

/// Parse a Safaricom STK TransactionDate integer (YYYYMMDDHHmmss, EAT) to
/// ISO 8601 UTC. Returns null if the value is malformed.
String? _parseEatTimestamp(String raw) {
  if (raw.length != 14) return null;
  try {
    final year = int.parse(raw.substring(0, 4));
    final month = int.parse(raw.substring(4, 6));
    final day = int.parse(raw.substring(6, 8));
    final hour = int.parse(raw.substring(8, 10));
    final minute = int.parse(raw.substring(10, 12));
    final second = int.parse(raw.substring(12, 14));
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

/// Parse a Safaricom B2C TransactionCompletedDateTime string
/// ("DD.MM.YYYY HH:mm:ss", EAT) to ISO 8601 UTC.
/// Returns null if the value is malformed.
String? _parseB2cTimestamp(String raw) {
  // Expected format: "22.03.2024 12:00:00"
  try {
    final parts = raw.split(' ');
    if (parts.length != 2) return null;
    final dateParts = parts[0].split('.');
    final timeParts = parts[1].split(':');
    if (dateParts.length != 3 || timeParts.length != 3) return null;

    final day = int.parse(dateParts[0]);
    final month = int.parse(dateParts[1]);
    final year = int.parse(dateParts[2]);
    final hour = int.parse(timeParts[0]);
    final minute = int.parse(timeParts[1]);
    final second = int.parse(timeParts[2]);

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
