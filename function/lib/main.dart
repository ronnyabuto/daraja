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
