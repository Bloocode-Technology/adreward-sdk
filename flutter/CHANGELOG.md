## 1.0.0

First public release.

- Reports app installs to AdReward on first open and surfaces the one-time
  claim link when the server recognises the opener.
- `onClaimAvailable` callback so the host app can show its own prompt instead
  of opening a browser at startup.
- Retries an unmatched open for the length of the attribution window, so a
  customer who clicked on one network and installed on another is not silently
  locked out.
- Network timeout so a slow connection never holds up app startup.
- Uses `defaultTargetPlatform` instead of `dart:io`, so the package imports
  cleanly on web.
