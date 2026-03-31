import 'package:daraja/daraja.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chama_session.dart';
import '../models/pot_state.dart';
import 'payment_provider.dart';

/// Aggregates per-member payment states into a shared pot balance.
class PotNotifier extends Notifier<PotState> {
  PotNotifier(this._session);

  final ChamaSession _session;

  @override
  PotState build() => PotState.empty(
        target: _session.totalAmount,
        memberCount: _session.memberCount,
      );

  void onMemberPaid(int amount) {
    state = state.withPayment(amount);
  }
}

final potProvider =
    NotifierProvider<PotNotifier, PotState>(() => throw UnimplementedError());

/// Watches all member payments and drives the pot.
///
/// Create this provider once per session with [ProviderScope.overrides].
Provider<void> makePotSyncProvider(ChamaSession session) {
  return Provider<void>((ref) {
    for (final member in session.members) {
      ref.listen<AsyncValue<PaymentState>>(
        memberPaymentProvider(member.id),
        (_, next) {
          if (next.value case PaymentSuccess(:final amount)) {
            ref.read(potProvider.notifier).onMemberPaid(amount);
          }
        },
      );
    }
  });
}
