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
final testMpesaTimestamp = DateTime.utc(2026, 4, 5, 11, 21, 15);

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

http.Response stkPushTransactionInProgress() => http.Response(
  jsonEncode({
    'ResponseCode': '1025',
    'ResponseDescription': 'Transaction already in progress, please try again.',
  }),
  200,
);

http.Response apiError(
  int statusCode, [
  String message = 'Internal Server Error',
]) => http.Response(
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
  DateTime? mpesaTimestamp,
}) {
  final settled = settledAt ?? DateTime.utc(2026, 3, 31, 12, 0, 0);
  final mpesaTs = mpesaTimestamp ?? testMpesaTimestamp;
  return appwrite_models.Document(
    $id: cid,
    $sequence: '1',
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
      'mpesaTimestamp': mpesaTs.toIso8601String(),
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
    $sequence: '1',
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
    $sequence: '1',
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
    $sequence: '1',
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

// ---------------------------------------------------------------------------
// B2C fixtures
// ---------------------------------------------------------------------------

const testOriginatorConversationId = 'a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d';
const testB2cCollectionId = 'disbursements';
const testB2cReceipt = 'OPH7RT61AB';
const testReceiverName = '0722000000 - Jane Doe';

http.Response b2cSuccess([
  String originatorId = testOriginatorConversationId,
]) => http.Response(
  jsonEncode({
    'ConversationID': 'AG_20240322_00007cdf9d70a7c6ab98',
    'OriginatorConversationID': originatorId,
    'ResponseCode': '0',
    'ResponseDescription': 'Accept the service request successfully.',
  }),
  200,
);

http.Response b2cRejected() => http.Response(
  jsonEncode({
    'ResponseCode': '2001',
    'ResponseDescription': 'Wrong credentials.',
  }),
  200,
);

appwrite_models.Document b2cSuccessDocument({
  String originatorId = testOriginatorConversationId,
  String receipt = testB2cReceipt,
  int amount = 500,
  DateTime? settledAt,
  DateTime? mpesaTimestamp,
}) {
  final settled = settledAt ?? DateTime.utc(2026, 4, 5, 10, 0, 0);
  final mpesaTs = mpesaTimestamp ?? DateTime.utc(2026, 4, 5, 9, 57, 0);
  return appwrite_models.Document(
    $id: originatorId,
    $sequence: '1',
    $collectionId: testB2cCollectionId,
    $databaseId: 'payments',
    $createdAt: settled.toIso8601String(),
    $updatedAt: settled.toIso8601String(),
    $permissions: ['read("user:$testUserId")'],
    data: {
      'originatorConversationId': originatorId,
      'conversationId': 'AG_20240322_00007cdf9d70a7c6ab98',
      'status': 'SUCCESS',
      'resultCode': 0,
      'receipt': receipt,
      'amount': amount,
      'receiverName': testReceiverName,
      'failureReason': null,
      'mpesaTimestamp': mpesaTs.toIso8601String(),
      'settledAt': settled.toIso8601String(),
    },
  );
}

appwrite_models.Document b2cFailedDocument({
  String originatorId = testOriginatorConversationId,
  int resultCode = 2001,
  String failureReason = 'Wrong credentials.',
}) {
  final now = DateTime.utc(2026, 4, 5, 10, 0, 0);
  return appwrite_models.Document(
    $id: originatorId,
    $sequence: '1',
    $collectionId: testB2cCollectionId,
    $databaseId: 'payments',
    $createdAt: now.toIso8601String(),
    $updatedAt: now.toIso8601String(),
    $permissions: ['read("user:$testUserId")'],
    data: {
      'originatorConversationId': originatorId,
      'conversationId': '',
      'status': 'FAILED',
      'resultCode': resultCode,
      'receipt': null,
      'amount': null,
      'receiverName': null,
      'failureReason': failureReason,
      'mpesaTimestamp': null,
      'settledAt': now.toIso8601String(),
    },
  );
}

appwrite_models.Document b2cTimeoutDocument({
  String originatorId = testOriginatorConversationId,
}) {
  final now = DateTime.utc(2026, 4, 5, 10, 0, 0);
  return appwrite_models.Document(
    $id: originatorId,
    $sequence: '1',
    $collectionId: testB2cCollectionId,
    $databaseId: 'payments',
    $createdAt: now.toIso8601String(),
    $updatedAt: now.toIso8601String(),
    $permissions: ['read("user:$testUserId")'],
    data: {
      'originatorConversationId': originatorId,
      'conversationId': '',
      'status': 'TIMEOUT',
      'resultCode': -1,
      'receipt': null,
      'amount': null,
      'receiverName': null,
      'failureReason': 'Request timed out.',
      'mpesaTimestamp': null,
      'settledAt': now.toIso8601String(),
    },
  );
}

RealtimeMessage b2cRealtimeMessage({
  required String status,
  String originatorId = testOriginatorConversationId,
  String receipt = testB2cReceipt,
  int amount = 500,
  int resultCode = 0,
  String? failureReason,
  String eventType = 'create',
  DateTime? mpesaTimestamp,
}) {
  final now = DateTime.utc(2026, 4, 5, 10, 0, 0);
  final mpesaTs = mpesaTimestamp ?? DateTime.utc(2026, 4, 5, 9, 57, 0);
  return RealtimeMessage(
    events: [
      'databases.payments.collections.$testB2cCollectionId'
          '.documents.$originatorId.$eventType',
    ],
    payload: {
      '\$id': originatorId,
      'originatorConversationId': originatorId,
      'conversationId': 'AG_20240322_00007cdf9d70a7c6ab98',
      'status': status,
      'resultCode': resultCode,
      'receipt': status == 'SUCCESS' ? receipt : null,
      'amount': status == 'SUCCESS' ? amount : null,
      'receiverName': status == 'SUCCESS' ? testReceiverName : null,
      'failureReason': failureReason,
      'mpesaTimestamp': status == 'SUCCESS' ? mpesaTs.toIso8601String() : null,
      'settledAt': now.toIso8601String(),
    },
    channels: [
      'databases.payments.collections.$testB2cCollectionId.documents.$originatorId',
    ],
    timestamp: now.toIso8601String(),
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
  DateTime? mpesaTimestamp,
}) {
  final now = DateTime.utc(2026, 3, 31, 12, 0, 0);
  final mpesaTs = mpesaTimestamp ?? testMpesaTimestamp;
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
      'mpesaTimestamp': status == 'SUCCESS' ? mpesaTs.toIso8601String() : null,
      'settledAt': now.toIso8601String(),
    },
    channels: ['databases.payments.collections.transactions.documents.$cid'],
    timestamp: now.toIso8601String(),
  );
}
