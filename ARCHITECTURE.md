# Architecture

How the package works and why the key decisions were made.

## The core problem

STK Push initiation is straightforward — one POST to Safaricom returns `ResponseCode: 0` and a `CheckoutRequestID`. The hard part is getting the result back to the Flutter UI in a timely, reliable way.

Safaricom delivers the result by POSTing to a developer-provided `CallbackURL`. That means you need a public HTTPS endpoint. Options:

1. Build and host a server yourself
2. Use a serverless function on a BaaS platform that gives you a stable public domain

Option 2 is the right choice for a Flutter package targeting developers who don't want to run a server. Appwrite Functions give you a stable domain (no cold-start URL rotation), a Dart runtime, and a database that triggers Realtime events when written to — which closes the loop back to the Flutter client without an additional polling call.

## Data flow

```
Flutter device
  │
  ├─ 1. OAuth token fetched from Safaricom (cached in memory, 60s buffer)
  ├─ 2. STK Push POSTed directly to Safaricom
  │       Response: CheckoutRequestID
  ├─ 3. CheckoutRequestID written to SharedPreferences
  ├─ 4. Appwrite Realtime subscription opened for that document
  │
  [customer receives USSD prompt, enters PIN]
  │
  Safaricom
  ├─ 5. POSTs callback to Appwrite Function domain
  │
  Appwrite Function
  ├─ 6. Parses callback, writes result document (documentId = CID)
  │       Returns {"ResultCode": 0} to Safaricom
  │
  Appwrite Realtime
  ├─ 7. DB write automatically fires Realtime event
  │
  Flutter device
  └─ 8. RealtimeMessage received → PaymentState emitted → stream closes
```

## Why direct-from-device STK Push

The alternative is routing the initiation through a server proxy. That adds a round-trip, a deployment dependency, and a point of failure that's entirely separate from the payment itself.

Appwrite Functions run server-side Dart. They could accept the initiation request, call Safaricom, and return the CID to the client. The problem is that Safaricom's callback arrives seconds to minutes later — so the function would have returned long before the result comes back. The callback still needs its own endpoint. You end up with two functions and a proxy that buys nothing.

The trade-off is that `consumerKey` and `consumerSecret` live in the app's build-time config. For a v1 package this is the developer's responsibility, consistent with how every Safaricom sandbox integration works. A proxied credential mode is a v2 concern.

## Realtime vs. polling

Realtime is the fast path. The Appwrite WebSocket connection receives the event milliseconds after the DB write. Polling is a fallback for three scenarios:

- App was backgrounded during the wait (PIN-entry flow — the most common real case)
- WebSocket disconnected and reconnected while the payment resolved
- App was killed and restarted

The polling schedule (T+10, T+30, T+70) mirrors what real device logs show for Safaricom's callback delivery timing. T+90 is the hard cutoff — `PaymentTimeout` is emitted and the subscription is closed.

`WidgetsBindingObserver` handles the backgrounding case. When the user returns from the M-Pesa app after entering their PIN, `didChangeAppLifecycleState(resumed)` triggers an immediate database poll rather than waiting for the next scheduled one.

## PaymentTimeout is not PaymentFailed

This distinction matters.

`PaymentFailed` means Safaricom confirmed the payment did not go through — insufficient funds, wrong PIN repeated, etc. The money did not move.

`PaymentTimeout` means the T+90 window elapsed with no callback. The payment may have succeeded on Safaricom's side. The receipt may exist in their ledger. The money may have left the customer's account. The package has no way to know.

Treating these identically in the UI causes double-payment scenarios: customer sees "payment failed", pays again, first payment receipt arrives later, both payments have processed.

`PaymentTimeout` intentionally has no `message` field and no `resultCode` field — there is no result to report. The correct response is neutral: "Payment status unknown. Check your M-Pesa messages or contact support."

## Duplicate callback handling

Safaricom retries the callback up to three times if it does not receive `ResultCode: 0` within its timeout. The function always returns `ResultCode: 0` — even if the DB write fails — so Safaricom stops retrying.

For duplicates that do arrive, the document ID is the `CheckoutRequestID`. The second `createDocument` call with the same ID throws an `AppwriteException` with code 409, which the function catches and ignores. The Flutter client has already received the terminal state from the first write. The stream is closed. The duplicate triggers a Realtime event that goes nowhere.

## SharedPreferences for killed-app recovery

`dart:isolate` memory doesn't survive a process kill. The only storage that persists across a force-kill is `SharedPreferences` (on Android, a file in the app's data directory; on iOS, `NSUserDefaults`). The `CheckoutRequestID` is written before the Realtime subscription opens. On next launch, `restorePendingPayment()` checks for it, queries the database directly, and either emits the terminal state immediately (if the payment resolved while the app was dead) or resumes the subscription.

## Idempotency

The same design that handles duplicate callbacks also handles any other scenario where the same CID appears more than once: `documentId = checkoutRequestId`. Appwrite enforces uniqueness at the document level. There is no separate deduplication logic, no `Set<String>` of seen IDs, no transaction needed.

## What is not in scope

B2C, C2B, account balance, reversals, Ratiba, Mini Apps. None of these are in v1. The package is deliberately narrow — STK Push, end to end. Scope creep in payment libraries is how bugs ship.
