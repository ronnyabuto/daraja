import 'dart:async';

import 'package:appwrite/appwrite.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../client/daraja_client.dart';
import '../models/daraja_config.dart';
import '../models/daraja_exception.dart';
import '../models/payment_state.dart';
import '../realtime/payment_subscription.dart';

const _prefKey = 'daraja_pending_cid';

// Polling schedule in seconds relative to STK Push initiation.
const _pollSchedule = [10, 30, 70];
const _timeoutSeconds = 90;

class PaymentNotifier with WidgetsBindingObserver {
  PaymentNotifier({
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

  final _controller = StreamController<PaymentState>.broadcast();

  PaymentSubscription? _subscription;
  Timer? _timeoutTimer;
  List<Timer> _pollTimers = [];
  String? _pendingCid;
  DateTime? _initiatedAt;

  Stream<PaymentState> get stream => _controller.stream;

  /// Checks for a payment pending from a previous session (killed app).
  /// Call this once during app initialisation, before any stkPush call.
  Future<void> restorePendingPayment() async {
    final prefs = SharedPreferencesAsync();
    final cid = await prefs.getString(_prefKey);
    if (cid == null) return;

    _pendingCid = cid;
    _emit(PaymentPending(
      checkoutRequestId: cid,
      initiatedAt: DateTime.now(),
    ));

    final resolved = await _pollNow(cid);
    if (resolved) return;

    _openSubscription(cid);
    _scheduleTimeout(cid);
  }

  Future<Stream<PaymentState>> initiate({
    required String phone,
    required int amount,
    required String reference,
    required String description,
    required String userId,
  }) async {
    _emit(const PaymentInitiating());

    final String cid;
    try {
      cid = await _darajaClient.initiateStkPush(
        phone: phone,
        amount: amount,
        reference: reference,
        description: description,
        userId: userId,
      );
    } on DarajaException catch (e) {
      _emit(PaymentError(message: e.message));
      return stream;
    } on FormatException catch (e) {
      _emit(PaymentError(message: e.message));
      return stream;
    } on ArgumentError catch (e) {
      _emit(PaymentError(message: e.message.toString()));
      return stream;
    }

    _pendingCid = cid;
    _initiatedAt = DateTime.now();

    final prefs = SharedPreferencesAsync();
    await prefs.setString(_prefKey, cid);

    _emit(PaymentPending(
      checkoutRequestId: cid,
      initiatedAt: _initiatedAt!,
    ));

    _openSubscription(cid);
    _schedulePolls(cid);
    _scheduleTimeout(cid);
    WidgetsBinding.instance.addObserver(this);

    return stream;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _pendingCid != null) {
      _pollNow(_pendingCid!);
    }
  }

  void _openSubscription(String cid) {
    _subscription = PaymentSubscription(
      databases: _databases,
      realtime: _realtime,
      config: _config,
      checkoutRequestId: cid,
    );

    _subscription!.stream.listen(
      _onTerminal,
      onError: (_) {},
    );
  }

  void _schedulePolls(String cid) {
    _pollTimers = _pollSchedule.map((seconds) {
      return Timer(Duration(seconds: seconds), () => _pollNow(cid));
    }).toList();
  }

  void _scheduleTimeout(String cid) {
    _timeoutTimer = Timer(const Duration(seconds: _timeoutSeconds), () {
      if (_pendingCid == cid) {
        _onTerminal(PaymentTimeout(checkoutRequestId: cid));
      }
    });
  }

  Future<bool> _pollNow(String cid) async {
    try {
      final state = await _subscription?.poll();
      if (state != null) {
        _onTerminal(state);
        return true;
      }
    } catch (_) {}
    return false;
  }

  void _onTerminal(PaymentState state) {
    if (_pendingCid == null) return;
    _cleanup();
    _emit(state);
  }

  void _emit(PaymentState state) {
    if (!_controller.isClosed) _controller.add(state);
  }

  void _cleanup() {
    _pendingCid = null;
    _initiatedAt = null;
    _subscription?.close();
    _subscription = null;
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    for (final t in _pollTimers) {
      t.cancel();
    }
    _pollTimers = [];
    WidgetsBinding.instance.removeObserver(this);
    SharedPreferencesAsync().remove(_prefKey);
  }

  void dispose() {
    _cleanup();
    _controller.close();
    _darajaClient.close();
  }
}
