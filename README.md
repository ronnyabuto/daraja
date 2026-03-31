# daraja

M-Pesa STK Push for Flutter, backed by Appwrite. One package, one deployed function, eight lines of app code.

```dart
final stream = await daraja.stkPush(
  phone: '0712345678',
  amount: 1000,
  reference: 'ORDER-001',
  description: 'Payment',
  userId: currentUser.id,
);

stream.listen((state) {
  switch (state) {
    case PaymentSuccess(:final receiptNumber, :final amount):
      showReceipt('KES $amount — $receiptNumber');
    case PaymentFailed(:final message):
      showError(message);
    case PaymentCancelled():
      showCancelled();
    case PaymentTimeout():
      // Money may have moved. Do not say "payment failed."
      showNeutralTimeout();
    case PaymentPending():
      showWaitingForPin();
    case PaymentInitiating():
      showSpinner();
    case PaymentError(:final message):
      showTechnicalError(message);
    case PaymentIdle():
      break;
  }
});
```

## What this solves

The standard M-Pesa integration problem is not initiating the STK Push — that part is one HTTP call. The problem is everything after it:

- The payment result arrives at a server you have to build yourself
- The customer backgrounds your app to enter their PIN in the M-Pesa app, and you miss the update
- Your tunnel dies mid-payment and the transaction is orphaned with no recovery path
- You build a polling loop and it produces 10–39 seconds of lag on every payment

This package handles all of it. The result arrives over Appwrite Realtime (WebSocket, sub-second delivery). App backgrounding is handled via `WidgetsBindingObserver`. Killed-app recovery runs on next launch from `SharedPreferences`. Polling is a fallback, not the primary path.

## How it works

Two pieces that work together:

**An Appwrite Function** (`function/`) deployed once to your Appwrite project. Its public domain becomes the `CallbackURL` for every STK Push. When Safaricom posts the payment result to it, the function writes a document to your Appwrite database — which automatically fires a Realtime event.

**The Flutter package** (`lib/`) initiates the STK Push directly from the device to Safaricom (no proxy), opens a Realtime subscription for that specific payment document, manages the timeout cascade, registers the lifecycle observer, and exposes everything as a single typed stream that closes when the payment reaches a terminal state.

## Setup

### 1. Appwrite

Create a database and collection with this schema:

| Attribute | Type | Required |
|---|---|---|
| `checkoutRequestId` | String (255) | Yes |
| `status` | String (20) | Yes |
| `resultCode` | Integer | No |
| `receipt` | String (20) | No |
| `amount` | Integer | No |
| `failureReason` | String (255) | No |
| `settledAt` | String (50) | Yes |

### 2. Deploy the function

```bash
cd function
appwrite functions createDeployment \
  --functionId=<your-function-id> \
  --entrypoint="lib/main.dart" \
  --code=.
```

In the Appwrite console, set Execute access to **Any** — Safaricom doesn't send auth headers. Add two environment variables:

```
DARAJA_DATABASE_ID = <your-database-id>
DARAJA_COLLECTION_ID = <your-collection-id>
```

Copy the generated function domain.

### 3. Configure and use

```dart
import 'package:daraja/daraja.dart';

final daraja = Daraja(
  config: DarajaConfig(
    consumerKey: 'xxx',
    consumerSecret: 'xxx',
    passkey: 'xxx',
    shortcode: '174379',
    environment: DarajaEnvironment.sandbox,
    appwriteEndpoint: 'https://cloud.appwrite.io/v1',
    appwriteProjectId: 'xxx',
    appwriteDatabaseId: 'payments',
    appwriteCollectionId: 'transactions',
    callbackDomain: 'https://64d4d22db370ae41a32e.fra.appwrite.run',
  ),
);

// On app startup — restore any payment pending from a previous session
await daraja.restorePendingPayment();

// Initiate a payment
final stream = await daraja.stkPush(
  phone: '0712345678',
  amount: 1000,
  reference: 'ORDER-001',  // max 12 characters
  description: 'Payment',  // max 13 characters
  userId: currentUser.id,
);
```

## Phone number formats

All standard Kenyan formats are accepted and normalised to `2547XXXXXXXX` / `2541XXXXXXXX`:

- `0712345678`
- `712345678`
- `+254712345678`
- `254712345678`

Anything else throws a `FormatException` before the API call.

## PaymentTimeout

`PaymentTimeout` is not `PaymentFailed`. It means the 90-second wait elapsed with no callback. Money may have been deducted. The receipt may exist on Safaricom's ledger. Do not tell the customer their payment failed — show neutral status and a support path.

## Free tier note

Appwrite pauses free-tier projects after one week of inactivity. A payment app that goes quiet will silently drop Safaricom callbacks. Either set up a weekly keep-warm ping or use a paid tier for any production workload.

## Running the demo

```bash
cd example/chama
flutter run \
  --dart-define=DARAJA_CONSUMER_KEY=<key> \
  --dart-define=DARAJA_CONSUMER_SECRET=<secret> \
  --dart-define=DARAJA_PASSKEY=<passkey> \
  --dart-define=APPWRITE_PROJECT_ID=<id> \
  --dart-define=APPWRITE_DATABASE_ID=payments \
  --dart-define=APPWRITE_COLLECTION_ID=transactions \
  --dart-define=CALLBACK_DOMAIN=https://<fn-domain>.appwrite.run
```

The demo is a chama split-bill app — three members each paying their share via concurrent STK Pushes, with a live shared pot that updates as payments land.

## Running the tests

Unit tests (no external dependencies):

```bash
flutter test
```

Integration tests (requires [Pesa Playground](https://github.com/OmentaElvis/pesa-playground) running locally):

```bash
pesa-playground --port 3000

flutter test test/integration/ --tags integration \
  --dart-define=DARAJA_CONSUMER_KEY=<key> \
  --dart-define=DARAJA_CONSUMER_SECRET=<secret> \
  --dart-define=DARAJA_PASSKEY=<passkey> \
  --dart-define=APPWRITE_ENDPOINT=https://cloud.appwrite.io/v1 \
  --dart-define=APPWRITE_PROJECT_ID=<id> \
  --dart-define=APPWRITE_DATABASE_ID=<db> \
  --dart-define=APPWRITE_COLLECTION_ID=<col> \
  --dart-define=CALLBACK_DOMAIN=<domain> \
  --dart-define=APPWRITE_USER_ID=<uid>
```
