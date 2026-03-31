import 'package:daraja/daraja.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chama_member.dart';
import 'daraja_provider.dart';

/// Notifier for a single member's payment stream.
class MemberPaymentNotifier extends AutoDisposeAsyncNotifier<PaymentState> {
  @override
  Future<PaymentState> build() async => const PaymentIdle();

  Future<void> pay({
    required ChamaMember member,
    required int amount,
    required String reference,
  }) async {
    state = const AsyncValue.loading();

    final daraja = ref.read(darajaProvider);
    final stream = await daraja.stkPush(
      phone: member.phone,
      amount: amount,
      reference: reference,
      description: 'Chama',
      userId: member.userId,
    );

    await for (final s in stream) {
      state = AsyncValue.data(s);
    }
  }
}

/// One provider per member — keyed by [ChamaMember.id].
final memberPaymentProvider = AutoDisposeAsyncNotifierProvider.family<
    MemberPaymentNotifier, PaymentState, String>(
  MemberPaymentNotifier.new,
);
