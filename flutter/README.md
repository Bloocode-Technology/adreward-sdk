# adreward_attribution

Install-attribution SDK for advertisers running AdReward App-Install campaigns.
Same behaviour on Android and iOS, no platform channels.

## Install

```yaml
dependencies:
  adreward_attribution:
    git:
      url: https://github.com/Bloocode-Technology/adreward-sdk
      path: flutter
      ref: v1.0.0
```

## Use

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AdReward.init(
    trackingId: 'ADR-XXXXXX',
    onClaimAvailable: (claimUrl) => showMyPrompt(claimUrl),
  );

  runApp(const MyApp());
}
```

`trackingId` comes from your app registration in the AdReward advertiser
dashboard.

Omit `onClaimAvailable` and the SDK opens the claim link itself. Prefer the
callback: showing your own prompt and opening the link on a user tap avoids an
unexplained jump to the browser at startup, which Apple reviewers dislike.

See `example/` for a complete integration.

## How it works

1. A customer taps **Install** on AdReward (logged in) → AdReward records the
   click with their account and IP.
2. They install and open your app.
3. On open, the SDK calls `POST /api/v1/sdk/install`.
4. If AdReward finds a recent matching click, it returns a one-time claim URL.
   Opened in the **external browser**, the customer's existing AdReward session
   confirms the claim and they are paid.
5. Organic installs get `no_match` and nothing is shown.

The SDK never collects personal data. It sends a random per-install UUID, the
platform, and your tracking id — nothing else.

## Options

| Option | Default | Purpose |
|---|---|---|
| `trackingId` | — | **Required.** Your app's AdReward tracking id |
| `apiBase` | `https://api.earn4rmads.com` | AdReward API base URL |
| `onClaimAvailable` | `null` | Show your own prompt instead of auto-opening |
| `retryWindowHours` | `72` | How long an unmatched open keeps retrying |
| `timeout` | `10s` | Network timeout |
| `debug` | `false` | Log SDK activity |

`AdReward.reset()` clears local state so `init()` runs again — for testing.

## Licence

MIT
