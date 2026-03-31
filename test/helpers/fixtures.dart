import 'dart:convert';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as appwrite_models;
import 'package:daraja/src/models/daraja_config.dart';
import 'package:http/http.dart' as http;

const testConfig = DarajaConfig(
  consumerKey: 'test_consumer_key',
  consumerSecret: 'test_consumer_secret',
  passkey: 'test_passkey',
  shortcode: '174379',
  environment: DarajaEnvironment.sandbox,
  appwriteEndpoint: 'https://cloud.appwrite.io/v1',
  appwriteProjectId: 'test_project',
  appwriteDatabaseId: 'payments',
  appwriteCollectionId: 'transactions',
  callbackDomain: 'https://fn.appwrite.run',
);

const testCid = 'ws_CO_191220191020363925';
const testUserId = 'user_abc123';
const testReceipt = 'NLJ7RT61SV';

http.Response oauthSuccess() => http.Response(
      jsonEncode({'access_token': 'test_access_token', 'expires_in': '3599'}),
      200,
    );

http.Response stkPushSuccess([String cid = testCid]) => http.Response(
      jsonEncode({
        'MerchantRequestID': 'mr_29115-34620561-1',
        'CheckoutRequestID': cid,
        'ResponseCode': '0',
        'ResponseDescription': 'Success. Request accepted for processing',
        'CustomerMessage': 'Success. Request accepted for processing',
      }),
      200,
    );

http.Response stkPushRejected() => http.Response(
      jsonEncode({
        'ResponseCode': '1',
        'ResponseDescription': 'The balance is insufficient for the transaction',
      }),
      200,
    );

http.Response apiError(int statusCode, [String message = 'Internal Server Error']) =>
    http.Response(
      jsonEncode({'errorCode': 'SERVER_ERROR', 'errorMessage': message}),
      statusCode,
    );

http.Response stkQueryPending() => http.Response(
      jsonEncode({
        'ResponseCode': '0',
        'ResponseDescription': 'The service request has been accepted',
        'MerchantRequestID': 'mr_123',
        'CheckoutRequestID': testCid,
        'ResultCode': '17',
        'ResultDesc': 'Request is being processed',
      }),
      200,
    );

http.Response stkQuerySuccess() => http.Response(
      jsonEncode({
        'ResponseCode': '0',
        'ResponseDescription': 'The service request has been accepted',
        'MerchantRequestID': 'mr_123',
        'CheckoutRequestID': testCid,
        'ResultCode': '0',
        'ResultDesc': 'The service request is processed successfully.',
      }),
      200,
    );

http.Response stkQueryCancelled() => http.Response(
      jsonEncode({
        'ResponseCode': '0',
        'MerchantRequestID': 'mr_123',
        'CheckoutRequestID': testCid,
        'ResultCode': '1032',
        'ResultDesc': 'Request cancelled by user.',
      }),
      200,
    );

appwrite_models.Document successDocument({
  String cid = testCid,
  String receipt = testReceipt,
  int amount = 1000,
  DateTime? settledAt,
}) {
  final settled = settledAt ?? DateTime.utc(2026, 3, 31, 12, 0, 0);
  return appwrite_models.Document(
    $id: cid,
    $collectionId: 'transactions',
    $databaseId: 'payments',
    $createdAt: settled.toIso8601String(),
    $updatedAt: settled.toIso8601String(),
    $permissions: ['read("user:$testUserId")'],
    data: {
      'checkoutRequestId': cid,
      'status': 'SUCCESS',
      'resultCode': 0,
      'receipt': receipt,
      'amount': amount,
      'failureReason': null,
      'settledAt': settled.toIso8601String(),
    },
  );
}

appwrite_models.Document failedDocument({
  String cid = testCid,
  int resultCode = 1031,
  String failureReason = 'Insufficient funds in the account',
}) {
  final now = DateTime.utc(2026, 3, 31, 12, 0, 0);
  return appwrite_models.Document(
    $id: cid,
    $collectionId: 'transactions',
    $databaseId: 'payments',
    $createdAt: now.toIso8601String(),
    $updatedAt: now.toIso8601String(),
    $permissions: ['read("user:$testUserId")'],
    data: {
      'checkoutRequestId': cid,
      'status': 'FAILED',
      'resultCode': resultCode,
      'receipt': null,
      'amount': null,
      'failureReason': failureReason,
      'settledAt': now.toIso8601String(),
    },
  );
}

appwrite_models.Document cancelledDocument({String cid = testCid}) {
  final now = DateTime.utc(2026, 3, 31, 12, 0, 0);
  return appwrite_models.Document(
    $id: cid,
    $collectionId: 'transactions',
    $databaseId: 'payments',
    $createdAt: now.toIso8601String(),
    $updatedAt: now.toIso8601String(),
    $permissions: ['read("user:$testUserId")'],
    data: {
      'checkoutRequestId': cid,
      'status': 'CANCELLED',
      'resultCode': 1032,
      'receipt': null,
      'amount': null,
      'failureReason': 'Request cancelled by user.',
      'settledAt': now.toIso8601String(),
    },
  );
}

appwrite_models.Document timeoutDocument({String cid = testCid}) {
  final now = DateTime.utc(2026, 3, 31, 12, 0, 0);
  return appwrite_models.Document(
    $id: cid,
    $collectionId: 'transactions',
    $databaseId: 'payments',
    $createdAt: now.toIso8601String(),
    $updatedAt: now.toIso8601String(),
    $permissions: ['read("user:$testUserId")'],
    data: {
      'checkoutRequestId': cid,
      'status': 'TIMEOUT',
      'resultCode': 1037,
      'receipt': null,
      'amount': null,
      'failureReason': 'The transaction timed out.',
      'settledAt': now.toIso8601String(),
    },
  );
}

RealtimeMessage realtimeMessage({
  required String status,
  required String cid,
  String receipt = testReceipt,
  int amount = 1000,
  int resultCode = 0,
  String? failureReason,
  String eventType = 'create',
}) {
  final now = DateTime.utc(2026, 3, 31, 12, 0, 0);
  return RealtimeMessage(
    events: [
      'databases.payments.collections.transactions.documents.$cid.$eventType',
    ],
    payload: {
      '\$id': cid,
      'checkoutRequestId': cid,
      'status': status,
      'resultCode': resultCode,
      'receipt': status == 'SUCCESS' ? receipt : null,
      'amount': status == 'SUCCESS' ? amount : null,
      'failureReason': failureReason,
      'settledAt': now.toIso8601String(),
    },
    channels: [
      'databases.payments.collections.transactions.documents.$cid',
    ],
    timestamp: now.toIso8601String(),
  );
}
