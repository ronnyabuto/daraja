# daraja callback function

The Appwrite Function that receives M-Pesa STK Push callbacks from Safaricom, writes the result to Appwrite Database, and triggers the Realtime event that updates your Flutter UI.

Deploy this once per Appwrite project. It takes about five minutes.

---

## Prerequisites

- [Appwrite Cloud](https://cloud.appwrite.io) account or self-hosted Appwrite 1.9+
- [Appwrite CLI](https://appwrite.io/docs/tooling/command-line/installation) installed

---

## Step 1 — Create database and collection

In the Appwrite Console, create a database (e.g. `payments`) and a collection (e.g. `transactions`) with these attributes:

| Attribute | Type | Size | Required |
|---|---|---|---|
| `checkoutRequestId` | String | 255 | Yes |
| `status` | String | 20 | Yes |
| `resultCode` | Integer | — | No |
| `receipt` | String | 20 | No |
| `amount` | Integer | — | No |
| `failureReason` | String | 255 | No |
| `settledAt` | String | 50 | Yes |

Collection permissions: leave empty — the function sets per-document permissions on write.

---

## Step 2 — Create the function

```bash
appwrite functions create \
  --name "daraja-callback" \
  --runtime dart-3.8
```

Note the function ID from the output.

---

## Step 3 — Deploy

From the `function/` directory:

```bash
cd function
dart pub get
appwrite functions createDeployment \
  --functionId <your-function-id> \
  --entrypoint "lib/main.dart" \
  --code "." \
  --activate true
```

---

## Step 4 — Set environment variables

In the Appwrite Console → Functions → your function → Settings → Variables:

| Variable | Value |
|---|---|
| `DARAJA_DATABASE_ID` | Your database ID (e.g. `payments`) |
| `DARAJA_COLLECTION_ID` | Your collection ID (e.g. `transactions`) |

`APPWRITE_FUNCTION_API_ENDPOINT`, `APPWRITE_FUNCTION_PROJECT_ID`, and `APPWRITE_API_KEY` are injected automatically — do not add them.

---

## Step 5 — Set execute access

Console → Functions → your function → Settings → Permissions

Set **Execute access** to `Any`.

This allows Safaricom's servers to POST callbacks without authentication headers.

---

## Step 6 — Copy the function domain

Console → Functions → your function → Domains

Copy the generated domain. It looks like:

```
https://64d4d22db370ae41a32e.fra.appwrite.run
```

Use this as `callbackDomain` in your `DarajaConfig`:

```dart
final config = DarajaConfig(
  // ...
  callbackDomain: 'https://64d4d22db370ae41a32e.fra.appwrite.run',
);
```

---

## Free tier note

Appwrite Cloud pauses projects after **one week of inactivity**. If your project goes quiet, Safaricom callbacks will arrive at an unreachable URL and be lost.

For any production workload, upgrade to the Pro plan ($25/month). For development, set up a weekly scheduled function ping to keep the project active.

---

## Testing locally

Use [Pesa Playground](https://github.com/OmentaElvis/pesa-playground) to simulate callbacks with failure states (insufficient funds, cancellation, timeout) that the official Daraja sandbox cannot produce.

Point Pesa Playground's callback URL at your deployed function domain during development.
