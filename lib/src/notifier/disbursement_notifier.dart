import 'dart:async';
import 'dart:developer';
import 'dart:math' hide log;

import 'package:appwrite/appwrite.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../client/daraja_client.dart';
import '../models/b2c_command_id.dart';
import '../models/daraja_config.dart';
import '../models/disbursement_state.dart';

const _prefKey = 'daraja_pending_b2c_oid';

// Polling schedule in seconds relative to B2C initiation.
const _pollSchedule = [15, 45, 75];
const _timeoutSeconds = 90;

class DisbursementNotifier with WidgetsBindingObserver {
  DisbursementNotifier({
    required DarajaConfig config,
    required Databases databases,
    required Realtime realtime,
    required DarajaClient darajaClient,
  })  : _config = config,
        _databases = databases,
        _realtime = realtime,
        _darajaClient = darajaClient;

  final DarajaConfig _config;
  final Databases _databases;
  final Realtime _realtime;
  final DarajaClient _darajaClient;

  final _controller = StreamController<DisbursementState>.broadcast();

  RealtimeSubscription? _realtimeSub;
  Timer? _timeoutTimer;
  List<Timer> _pollTimers = [];
  String? _pendingOid;

  Stream<DisbursementState> get stream => _controller.stream;

  /// Checks for a B2C disbursement pending from a previous session (killed app).
  /// Call once during app initialisation, before any b2cPush call.
  Future<void> restorePendingDisbursement() async {
    final collectionId = _config.b2cCollectionId;
    if (collectionId == null) return;

    final prefs = SharedPreferencesAsync();
    final oid = await prefs.getString(_prefKey);
    if (oid == null) return;

    _pendingOid = oid;
    _emit(DisbursementPending(originatorConversationId: oid));

    _openSubscription(oid, collectionId);

    final resolved = await _pollNow(oid, collectionId);
    if (resolved) return;

    _scheduleTimeout(oid);
  }

  Future<Stream<DisbursementState>> initiate({
    required String phone,
    required int amount,
    required String initiatorName,
    required String securityCredential,
    required B2cCommandId commandId,
    required String remarks,
    String? occasion,
    required String userId,
    required String collectionId,
  }) async {
    final oid = _generateUuid();

    _emit(DisbursementInitiating());

    // Subscribe before the network call — closes the race between Safaricom
    // accepting the request and the callback arriving at the Appwrite Function.
    _openSubscription(oid, collectionId);

    try {
      await _darajaClient.initiateB2c(
        originatorConversationId: oid,
        phone: phone,
        amount: amount,
        initiatorName: initiatorName,
        securityCredential: securityCredential,
        commandId: commandId,
        remarks: remarks,
        occasion: occasion,
        userId: userId,
      );
    } catch (_) {
      _closeSubscription();
      rethrow;
    }

    _pendingOid = oid;
    await SharedPreferencesAsync().setString(_prefKey, oid);

    _emit(DisbursementPending(originatorConversationId: oid));
    _schedulePolls(oid, collectionId);
    _scheduleTimeout(oid);
    WidgetsBinding.instance.addObserver(this);

    return stream;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final collectionId = _config.b2cCollectionId;
    if (state == AppLifecycleState.resumed &&
        _pendingOid != null &&
        collectionId != null) {
      _pollNow(_pendingOid!, collectionId);
    }
  }

  void _openSubscription(String oid, String collectionId) {
    _closeSubscription();
    final channel = 'databases.${_config.appwriteDatabaseId}'
        '.collections.$collectionId'
        '.documents.$oid';
    _realtimeSub = _realtime.subscribe([channel]);
    _realtimeSub!.stream.listen((message) {
      final isRelevant = message.events.any(
        (e) => e.contains('.create') || e.contains('.update'),
      );
      if (!isRelevant) return;

      final parsed = _parseDisbursementDocument(message.payload, oid);
      if (parsed == null) return;

      _onTerminal(parsed);
    }, onError: (_) {});
  }

  void _schedulePolls(String oid, String collectionId) {
    _pollTimers = _pollSchedule.map((seconds) {
      return Timer(
        Duration(seconds: seconds),
        () => _pollNow(oid, collectionId),
      );
    }).toList();
  }

  void _scheduleTimeout(String oid) {
    _timeoutTimer = Timer(const Duration(seconds: _timeoutSeconds), () {
      if (_pendingOid == oid) {
        _onTerminal(DisbursementTimeout(originatorConversationId: oid));
      }
    });
  }

  Future<bool> _pollNow(String oid, String collectionId) async {
    try {
      // Databases API is kept over TablesDB — Realtime document channels only
      // exist on the Databases service. TablesDB has no equivalent channel.
      // ignore: deprecated_member_use
      final doc = await _databases.getDocument(
        databaseId: _config.appwriteDatabaseId,
        collectionId: collectionId,
        documentId: oid,
      );
      final parsed = _parseDisbursementDocument(doc.data, oid);
      if (parsed != null) {
        _onTerminal(parsed);
        return true;
      }
    } catch (e) {
      log('poll error — $e', name: 'daraja');
    }
    return false;
  }

  void _onTerminal(DisbursementState state) {
    if (_pendingOid == null) return;
    _cleanup();
    _emit(state);
  }

  void _emit(DisbursementState state) {
    if (!_controller.isClosed) _controller.add(state);
  }

  void _closeSubscription() {
    final sub = _realtimeSub;
    if (sub != null) unawaited(sub.close());
    _realtimeSub = null;
  }

  void _cleanup() {
    _pendingOid = null;
    _closeSubscription();
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    for (final t in _pollTimers) {
      t.cancel();
    }
    _pollTimers = [];
    WidgetsBinding.instance.removeObserver(this);
    unawaited(SharedPreferencesAsync().remove(_prefKey));
  }

  void dispose() {
    _cleanup();
    _controller.close();
  }
}

DisbursementState? _parseDisbursementDocument(
  Map<String, dynamic> data,
  String oid,
) {
  final status = data['status'] as String?;
  return switch (status) {
    'SUCCESS' when data['receipt'] is String && data['amount'] is int =>
      DisbursementSuccess(
        originatorConversationId: oid,
        conversationId: data['conversationId'] as String? ?? '',
        receiptNumber: data['receipt'] as String,
        amount: data['amount'] as int,
        receiverName: data['receiverName'] as String? ?? '',
        settledAt: DateTime.parse(data['settledAt'] as String),
        mpesaTimestamp: data['mpesaTimestamp'] != null
            ? DateTime.parse(data['mpesaTimestamp'] as String)
            : null,
      ),
    'FAILED' => DisbursementFailed(
      originatorConversationId: oid,
      resultCode: data['resultCode'] as int,
      message: data['failureReason'] as String? ?? '',
    ),
    'TIMEOUT' => DisbursementTimeout(originatorConversationId: oid),
    _ => null,
  };
}

String _generateUuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}'
      '-${hex.substring(12, 16)}-${hex.substring(16, 20)}'
      '-${hex.substring(20)}';
}
