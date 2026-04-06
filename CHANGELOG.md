# Changelog

## 0.1.1 — 2026-04-06

- Added dartdoc comments across all public API elements (exceeds pub.dev 20% threshold).
- Added `example/lib/main.dart` minimal Flutter example for pub.dev scoring.
- Added B2C disbursement support: `Daraja.b2cPush()`, `DisbursementState` sealed class, `B2cCommandId`, `SecurityCredential`.

## 0.1.0 — 2026-03-31

Initial release.

**Core package**
- `Daraja` — public entry point. `stkPush()` returns a `Stream<PaymentState>` that closes on terminal state. `restorePendingPayment()` recovers any session killed before the payment resolved.
- `DarajaConfig` — typed config with `DarajaEnvironment.sandbox` / `production` toggle.
- `PaymentState` — sealed class with 8 states: `PaymentIdle`, `PaymentInitiating`, `PaymentPending`, `PaymentSuccess`, `PaymentFailed`, `PaymentCancelled`, `PaymentTimeout`, `PaymentError`.
- `DarajaClient` — direct HTTP to Safaricom. OAuth with in-memory token cache (60-second buffer). EAT password generation. Phone normalisation for all six Kenyan formats.
- `PaymentSubscription` — Appwrite Realtime subscription on a single document channel. Database poll fallback on reconnection.
- `PaymentNotifier` — orchestrates the full flow. `WidgetsBindingObserver` for foreground-resume polling. Timeout cascade at T+10, T+30, T+70 seconds. Hard cutoff at T+90 → `PaymentTimeout`. `SharedPreferences` persistence for killed-app recovery.

**Appwrite Function** (`function/`)
- Dart runtime callback handler. Parses Safaricom STK Push callback, writes result document to Appwrite Database. Uses `documentId = checkoutRequestId` for idempotent duplicate handling. Returns `ResultCode: 0` unconditionally so Safaricom stops retrying.

**Demo** (`example/chama/`)
- Split-bill chama app demonstrating concurrent per-member payments, shared pot aggregation, all terminal state variants, and killed-app recovery.
