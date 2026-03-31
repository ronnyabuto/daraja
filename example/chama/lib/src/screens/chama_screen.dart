import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chama_member.dart';
import '../models/chama_session.dart';
import '../models/pot_state.dart';
import '../providers/pot_provider.dart';
import '../widgets/member_tile.dart';
import '../widgets/pot_progress_card.dart';

class ChamaScreen extends ConsumerWidget {
  const ChamaScreen({super.key, required this.session});

  final ChamaSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pot = ref.watch(potProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(session.title),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: pot.isComplete
              ? const LinearProgressIndicator(
                  value: 1,
                  backgroundColor: Colors.transparent,
                  color: Colors.green,
                )
              : const SizedBox.shrink(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PotProgressCard(pot: pot, title: session.title),
          const SizedBox(height: 16),
          Text(
            'Members',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          ...session.members.map(
            (m) => MemberTile(
              member: m,
              amount: session.sharePerMember,
              reference: _ref(session.title),
            ),
          ),
          const SizedBox(height: 24),
          _SummaryRow(pot: pot, session: session),
        ],
      ),
    );
  }

  static String _ref(String title) {
    final slug = title.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    return slug.length > 12 ? slug.substring(0, 12) : slug;
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.pot, required this.session});

  final PotState pot;
  final ChamaSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Summary', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            _Row('Total target', 'KES ${session.totalAmount}'),
            _Row('Per member', 'KES ${session.sharePerMember}'),
            _Row('Collected', 'KES ${pot.collected}'),
            _Row('Remaining', 'KES ${session.totalAmount - pot.collected}'),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(value, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
