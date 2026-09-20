/**
 * AdReward Attribution SDK (React Native / Expo).
 *
 * Zero native code. On app open it tells AdReward an install happened; if
 * AdReward recognises the opener as a user who recently clicked the campaign
 * (matched server-side by IP within the attribution window), it returns a
 * one-time claim URL. That URL is opened in the EXTERNAL browser so the
 * customer's existing AdReward session on earn4rmads.com is reused — they
 * never log in again. Organic installs get `no_match` and nothing is shown.
 *
 * Drop-in usage (call once, early in app startup):
 *   AdReward.init({ trackingId: 'ADR-XXXXXX' })
 *
 * Recommended for App Store review — show your own prompt instead of sending
 * the customer straight to a browser on launch:
 *   AdReward.init({
 *     trackingId: 'ADR-XXXXXX',
 *     onClaimAvailable: (claimUrl) => showMyModal(claimUrl),
 *   })
 */
import AsyncStorage from '@react-native-async-storage/async-storage';
import { Linking, Platform } from 'react-native';

export type AdRewardConfig = {
  /** The advertiser app's tracking id (ADR-XXXXXX) from the AdReward dashboard. */
  trackingId: string;
  /** Base URL of the AdReward API, no trailing slash. */
  apiBase?: string;
  /** Override the detected platform if needed. */
  platform?: 'android' | 'ios';
  /**
   * Called when a claim is available, instead of opening the browser directly.
   * Strongly recommended: present your own in-app prompt and open the URL on a
   * user tap. Apple reviewers dislike an app that launches a browser on its own
   * at startup, and an unexplained jump to Safari reads as a bug to customers.
   *
   * Open it yourself with `Linking.openURL(claimUrl)` when they tap.
   */
  onClaimAvailable?: (claimUrl: string) => void;
  /**
   * How long to keep asking after an unmatched open, in hours. Must not exceed
   * the server's attribution window (72h by default) — past that the click can
   * no longer be honoured. Default 72.
   */
  retryWindowHours?: number;
  /** Network timeout in milliseconds. Default 10000. */
  timeoutMs?: number;
  /** Log SDK activity for debugging. */
  debug?: boolean;
};

const DEFAULT_API_BASE = 'https://api.earn4rmads.com';
const DEVICE_ID_KEY = 'adr_device_id';
const SETTLED_KEY = 'adr_attr_settled';
const FIRST_SEEN_KEY = 'adr_attr_first_seen';

/** RFC4122-ish v4 uuid — a per-install device id, not security-critical. */
function uuidv4(): string {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    const v = c === 'x' ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}

async function getDeviceId(): Promise<string> {
  let id = await AsyncStorage.getItem(DEVICE_ID_KEY);
  if (!id) {
    id = uuidv4();
    await AsyncStorage.setItem(DEVICE_ID_KEY, id);
  }
  return id;
}

/**
 * First time we ran on this device, as epoch ms. Bounds how long an unmatched
 * install keeps retrying.
 */
async function getFirstSeen(): Promise<number> {
  const stored = await AsyncStorage.getItem(FIRST_SEEN_KEY);
  if (stored) {
    const parsed = Number(stored);
    if (Number.isFinite(parsed)) {
      return parsed;
    }
  }

  const now = Date.now();
  await AsyncStorage.setItem(FIRST_SEEN_KEY, String(now));
  return now;
}

export const AdReward = {
  /**
   * Fire attribution. Safe to call on every app start — it self-guards, never
   * throws into the host app, and goes quiet once the outcome is settled.
   */
  async init(config: AdRewardConfig): Promise<void> {
    const log = (...a: unknown[]) => config.debug && console.log('[AdReward]', ...a);

    try {
      if (await AsyncStorage.getItem(SETTLED_KEY)) {
        log('already settled — skipping');
        return;
      }

      // An unmatched open is not final: the customer may have clicked on one
      // network and first opened the app on another, and the server re-runs the
      // IP gate on later opens. Keep asking until the attribution window is up.
      const retryWindowMs = (config.retryWindowHours ?? 72) * 3600 * 1000;
      const firstSeen = await getFirstSeen();
      if (Date.now() - firstSeen > retryWindowMs) {
        log('attribution window elapsed — settling');
        await AsyncStorage.setItem(SETTLED_KEY, '1');
        return;
      }

      const platform = config.platform ?? (Platform.OS === 'ios' ? 'ios' : 'android');
      const deviceId = await getDeviceId();
      const apiBase = (config.apiBase ?? DEFAULT_API_BASE).replace(/\/$/, '');

      // Never let a hanging network hold up app startup.
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), config.timeoutMs ?? 10000);

      let data: Record<string, unknown> = {};
      try {
        const res = await fetch(`${apiBase}/api/v1/sdk/install`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
          body: JSON.stringify({
            tracking_id: config.trackingId,
            platform,
            device_id: deviceId,
          }),
          signal: controller.signal,
        });

        const json = await res.json().catch(() => ({}));
        data = (json && (json as any).data) || {};
      } finally {
        clearTimeout(timer);
      }

      log('install response', data);

      const claimUrl = typeof data.claim_url === 'string' ? data.claim_url : null;

      if (claimUrl) {
        if (config.onClaimAvailable) {
          config.onClaimAvailable(claimUrl);
        } else {
          // External browser (never an in-app WebView) so the customer's
          // AdReward session cookie is reused and they skip logging in.
          await Linking.openURL(claimUrl);
        }

        // The claim was surfaced; do not surface it again on this device.
        await AsyncStorage.setItem(SETTLED_KEY, '1');
        return;
      }

      // `already_attributed` means this device is spent — stop asking. A plain
      // `no_match` is still open, so we retry on the next cold start until the
      // window above runs out.
      if (data.status === 'already_attributed') {
        log('device already attributed — settling');
        await AsyncStorage.setItem(SETTLED_KEY, '1');
      }
    } catch (e) {
      // Never break the host app. Not settling means we retry on the next open.
      log('error (will retry next open)', e);
    }
  },

  /** Testing helper: clear local state so init() runs again on the next call. */
  async reset(): Promise<void> {
    await AsyncStorage.multiRemove([DEVICE_ID_KEY, SETTLED_KEY, FIRST_SEEN_KEY]);
  },
};
