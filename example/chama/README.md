# Chama Demo

A split-bill chama app that demonstrates the full `daraja` package feature set
with real concurrent payments.

## What it shows

- **Concurrent STK Pushes** — each member pays their share independently.
- **Per-user Realtime subscriptions** — each member's document channel is
  subscribed separately; no member sees another's state.
- **Shared pot** — `PotNotifier` aggregates successful payments into a live
  running total and progress bar.
- **All terminal states** — success, failure, cancellation, and timeout each
  render a distinct UI state with correct messaging.
- **App lifecycle** — backgrounding to enter the M-Pesa PIN is handled
  transparently; `didChangeAppLifecycleState` polling resumes on foreground.
- **Killed-app recovery** — restart the app while a payment is pending and
  `restorePendingPayment()` picks it up from SharedPreferences.

## Running the demo

```bash
cd example/chama

flutter run \
  --dart-define=DARAJA_CONSUMER_KEY=<key> \
  --dart-define=DARAJA_CONSUMER_SECRET=<secret> \
  --dart-define=DARAJA_PASSKEY=<passkey> \
  --dart-define=APPWRITE_ENDPOINT=https://cloud.appwrite.io/v1 \
  --dart-define=APPWRITE_PROJECT_ID=<id> \
  --dart-define=APPWRITE_DATABASE_ID=<db> \
  --dart-define=APPWRITE_COLLECTION_ID=<col> \
  --dart-define=CALLBACK_DOMAIN=<fn-domain>
```

The demo is pre-configured with three members: Alice, Bob, and Carol, each
contributing KES 1,000 toward a KES 3,000 shared lunch bill.

Swap the phone numbers in `lib/src/config.dart` for your own sandbox numbers
before running.

## Architecture of the demo

```
main.dart
  └── ProviderScope
        ├── darajaProvider        — single Daraja instance (auto-disposed)
        ├── potProvider           — shared pot balance (overridden per session)
        ├── makePotSyncProvider   — wires payment streams → pot
        └── memberPaymentProvider — one per member, keyed by userId
              └── MemberPaymentNotifier.pay()
                    └── daraja.stkPush() → Stream<PaymentState>
```
