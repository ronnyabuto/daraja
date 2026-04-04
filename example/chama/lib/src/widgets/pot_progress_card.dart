import 'package:flutter/material.dart';

import '../models/pot_state.dart';

class PotProgressCard extends StatelessWidget {
  const PotProgressCard({super.key, required this.pot, required this.title});

  final PotState pot;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: pot.progress,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(
                pot.isComplete ? Colors.green : theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'KES ${pot.collected} / ${pot.target}',
                  style: theme.textTheme.bodyMedium,
                ),
                Text(
                  '${pot.paidCount}/${pot.memberCount} paid',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            if (pot.isComplete) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    'All members have paid',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
