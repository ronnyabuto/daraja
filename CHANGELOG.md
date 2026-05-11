# Changelog

## 0.1.2 — 2026-05-11

- Fixed B2C API endpoint (`/v3/` → `/v1/`).
- Added `Daraja.restorePendingDisbursement()` for killed-app recovery on B2C — mirrors `restorePendingPayment()`.
- Added `Daraja.disbursementStream` for a global B2C state listener, consistent with `Daraja.stream` for STK Push.
- B2C lifecycle (Realtime subscription, polling at T+15s/T+45s/T+75s, T+90s timeout, SharedPreferences persistence) extracted into `DisbursementNotifier`.
- Added `==` and `hashCode` to all `PaymentState` and `DisbursementState` subclasses.
- Replaced null-bang env var access in the Appwrite Function with a throwing `_env()` helper.

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
