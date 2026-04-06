// ignore_for_file: avoid_print
import 'package:daraja/daraja.dart';
import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Configuration — replace with your real credentials (never hardcode in prod).
// ---------------------------------------------------------------------------
final _daraja = Daraja(
  config: const DarajaConfig(
    consumerKey: 'YOUR_CONSUMER_KEY',
    consumerSecret: 'YOUR_CONSUMER_SECRET',
    passkey: 'YOUR_PASSKEY',
    shortcode: '174379',
    environment: DarajaEnvironment.sandbox,
    appwriteEndpoint: 'https://cloud.appwrite.io/v1',
    appwriteProjectId: 'YOUR_PROJECT_ID',
    appwriteDatabaseId: 'YOUR_DATABASE_ID',
    appwriteCollectionId: 'YOUR_COLLECTION_ID',
    callbackDomain: 'https://YOUR_FUNCTION.appwrite.run',
  ),
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Restore any payment that was pending when the app was previously killed.
  await _daraja.restorePendingPayment();
  runApp(const DarajaExampleApp());
}

class DarajaExampleApp extends StatelessWidget {
  const DarajaExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'daraja example',
      home: const PaymentPage(),
    );
  }
}

class PaymentPage extends StatefulWidget {
  const PaymentPage({super.key});

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  PaymentState _state = const PaymentIdle();

  Future<void> _pay() async {
    final stream = await _daraja.stkPush(
      phone: '0712345678',
      amount: 1,
      reference: 'ORDER-001',
      description: 'Example pay',
      userId: 'demo-user',
    );
    stream.listen((state) {
      setState(() => _state = state);
    });
  }

  @override
  void dispose() {
    _daraja.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('daraja example')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('State: ${_state.runtimeType}'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _state is PaymentIdle ? _pay : null,
              child: const Text('Pay KES 1'),
            ),
          ],
        ),
      ),
    );
  }
}
