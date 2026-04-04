import 'package:daraja/daraja.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chama_member.dart';
import '../providers/payment_provider.dart';
import 'payment_status_chip.dart';

class MemberTile extends ConsumerWidget {
  const MemberTile({
    super.key,
    required this.member,
    required this.amount,
    required this.reference,
  });

  final ChamaMember member;
  final int amount;
  final String reference;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncState = ref.watch(memberPaymentProvider(member.id));
    final state = asyncState.value ?? const PaymentIdle();
    final isTerminal =
        state is PaymentSuccess ||
        state is PaymentFailed ||
        state is PaymentCancelled ||
        state is PaymentTimeout;
    final isActive = state is PaymentInitiating || state is PaymentPending;

    return ListTile(
      leading: CircleAvatar(child: Text(member.name[0])),
      title: Text(member.name),
      subtitle: Text(member.phone, style: const TextStyle(fontSize: 12)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PaymentStatusChip(state: state),
          const SizedBox(width: 8),
          if (!isTerminal && !isActive)
            FilledButton.tonal(
              onPressed: () => ref
                  .read(memberPaymentProvider(member.id).notifier)
                  .pay(member: member, amount: amount, reference: reference),
              child: Text('KES $amount'),
            )
          else if (isActive)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }
}
