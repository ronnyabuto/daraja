import 'package:daraja/daraja.dart';
import 'package:flutter/material.dart';

class PaymentStatusChip extends StatelessWidget {
  const PaymentStatusChip({super.key, required this.state});

  final PaymentState state;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      PaymentIdle() => ('Awaiting', Colors.grey),
      PaymentInitiating() => ('Sending...', Colors.blue),
      PaymentPending() => ('Enter PIN', Colors.orange),
      PaymentSuccess() => ('Paid', Colors.green),
      PaymentFailed(:final message) => ('Failed: $message', Colors.red),
      PaymentCancelled() => ('Cancelled', Colors.red.shade300),
      PaymentTimeout() => ('Check M-Pesa', Colors.amber.shade800),
      PaymentError(:final message) => ('Error: $message', Colors.red),
    };

    return Chip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      backgroundColor: color.withAlpha(30),
      side: BorderSide(color: color, width: 1),
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}
