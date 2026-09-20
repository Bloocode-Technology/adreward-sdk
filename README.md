# AdReward Attribution SDK

Install-attribution SDKs for advertisers running AdReward App-Install campaigns.
Same behaviour on Android and iOS, no native code.

| Package | Path | Install |
|---|---|---|
| React Native / Expo — `@adreward/attribution` | `/` (repo root) | `npm i github:Bloocode-Technology/adreward-sdk#v1.0.0` |
| Flutter — `adreward_attribution` | `/flutter` | git dependency, `path: flutter` |

The React Native package sits at the repo root because **npm cannot install from
a subdirectory of a repository**. Flutter can, so it lives in `flutter/`. The
npm `files` list keeps `flutter/` out of the published tarball.

## How it works

1. A customer taps **Install** on AdReward (logged in) → AdReward records the
   click with their account and IP.
2. They install and open the advertiser's app.
3. On open, the SDK calls `POST /api/v1/sdk/install`.
4. If AdReward finds a recent click matching that IP within the attribution
   window, it returns a one-time **`claim_url`**. Opened in the **external
   browser**, the customer's existing AdReward session on `earn4rmads.com`
   confirms the claim and credits the reward — no second login.
5. Organic installs get `no_match` and **nothing is shown**.

The IP match only decides whether to *show* the prompt. Payout is decided
server-side by the customer's own session plus their open click, so the gate can
never pay the wrong person. An unmatched open is retried for the length of the
attribution window, because a customer may click on wifi and first open the app
on mobile data.

## Backend contract

```
POST {apiBase}/api/v1/sdk/install
Body: { "tracking_id": "ADR-XXXXXX", "platform": "android|ios", "device_id": "<per-install uuid>" }

Response (standard { message, data } envelope), data =
  { "status": "no_match" }                              → nothing to show; ask again later
  { "claim_url": "…", "install_token": "…", "expires_at": "…" }  → surface the claim
  { "status": "already_attributed" }                    → device settled; stop asking
```

`tracking_id` comes from the advertiser's app registration
(`POST /api/advertiser/apps`) in the AdReward dashboard.

## React Native / Expo

```ts
import { AdReward } from '@adreward/attribution';

// once, early in app startup (e.g. root layout):
AdReward.init({
  trackingId: 'ADR-XXXXXX',
  onClaimAvailable: (claimUrl) => showMyModal(claimUrl),
});
```

Peer deps: `@react-native-async-storage/async-storage`, `react-native`. Works in
both Expo and bare React Native — there is no Expo-only dependency.

## Flutter

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

Deps: `http`, `shared_preferences`, `url_launcher`. See `flutter/example/`.

## No SDK? Use the postback

Advertisers with their own backend can skip the SDK entirely and report installs
server-to-server with an HMAC-signed call to `POST /api/v1/postback`. See the
AdReward API docs.

## Notes for maintainers

- `npm run build` compiles `src/` to `dist/`. npm runs `prepare` automatically
  on git installs, so advertisers installing from GitHub get a built package.
- Publishing to npm / pub.dev is optional — git installs need no account. If you
  later publish, nothing about the package layout has to change.
- No device attestation in this version. Anti-fraud today is the deterministic
  login-based claim, one install row per device per app, and one campaign
  response per customer per campaign (enforced by a DB constraint). Attestation
  (Play Integrity / App Attest) exists in `git stash` on the backend repo and is
  worth revisiting before scaling real-money payouts.

## Licence

MIT
