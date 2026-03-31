import 'package:daraja/daraja.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/config.dart';
import 'src/models/chama_member.dart';
import 'src/models/chama_session.dart';
import 'src/models/pot_state.dart';
import 'src/providers/daraja_provider.dart';
import 'src/providers/pot_provider.dart';
import 'src/screens/chama_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final session = ChamaSession(
    title: demoTitle,
    totalAmount: demoTotal,
    members: [
      for (final (name, phone, userId) in demoMembers)
        ChamaMember(id: userId, name: name, phone: phone, userId: userId),
    ],
  );

  // Create daraja once and restore any pending payment before the first frame.
  final daraja = Daraja(config: demoConfig);
  await daraja.restorePendingPayment();

  // Build once — provider identity is stable for the app's lifetime.
  final potSync = makePotSyncProvider(session);

  runApp(
    ProviderScope(
      overrides: [
        potProvider.overrideWith(() => PotNotifier(session)),
        darajaProvider.overrideWithValue(daraja),
      ],
      child: ChamaApp(session: session, potSyncProvider: potSync),
    ),
  );
}

class ChamaApp extends ConsumerWidget {
  const ChamaApp({
    super.key,
    required this.session,
    required this.potSyncProvider,
  });

  final ChamaSession session;
  final Provider<void> potSyncProvider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(potSyncProvider);

    return MaterialApp(
      title: 'Chama Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF006B3F)),
        useMaterial3: true,
      ),
      home: ChamaScreen(session: session),
    );
  }
}
