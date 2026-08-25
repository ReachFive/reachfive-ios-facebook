# Manual test plan

`ConfiguredFacebookProvider.login` picks between two exchanges, recovers from a rejected token,
and hands off to the Facebook app or to a browser. None of it is covered by automated tests:
every branch needs a real Facebook session, a real tracking status.
Walk this list when changing the provider or bumping the Facebook SDK.

## Reading the log

The provider prints `[Reach5Facebook.Facebook] …` lines, **in `DEBUG` builds only**. Build the host
app with `SdkInternalConfig(loggingEnabled: true)` as well, to get the `➡️ REQUEST` / `⬅️ RESPONSE`
pairs with statuses and bodies.

Telling the two exchanges apart on the wire:

- **Classic** — a single `POST /identity/v1/oauth/provider/token`.
- **Limited** — `GET /oauth/authorize`, a 302 whose `Location` carries the code, then `POST /oauth/token`.

## Set-up recipes

The Set up column refers to these by name.

**Tracking on / off** — Settings › Privacy & Security › Tracking › (the app). Toggling it there
takes effect without reinstalling (or not, check the print to be sure).

**Classic session** — build with `prefersLoginTracking: .enabled`, Tracking on, log in once.
Leaves a stored access token behind.

**Limited session** — build with `prefersLoginTracking: .limited` (the default), log in once.
Leaves no access token behind, which is why the silent path never runs afterwards.

**No stored token** — call `logout()`, or reinstall. Nothing else clears it: no Graph API failure
does, so a revoked token stays in place until the next interactive login.

**Revoke the grant** — take the provider_token from the request body of the last classic exchange, then:

```sh
FB_TOKEN=the_token
curl -s -X DELETE "https://graph.facebook.com/v21.0/me/permissions" -H "Authorization: Bearer $FB_TOKEN"
curl -s "https://graph.facebook.com/v21.0/me?fields=id" -H "Authorization: Bearer $FB_TOKEN"
```

The second call must fail with code `190` (subcode `458` or `467`). If it still returns an id, the
revocation did not apply — most often the token belongs to another app; check with `debug_token`
that `data.app_id` is `1634029666893228`. Revoking de-authorizes the app entirely, and the next
login only re-requests the scopes the provider configuration lists, so anything granted beyond that
set is lost for that user.

## Scenarios

**A** path selection · **B** recovery from a rejected stored token · **C** interactive login outcomes ·
**D** app switch · **F** session lifecycle

| # | Set up | Run | Observe | Last run |
|---|---|---|---|---|
| A1 | No stored token, Tracking on, `prefersLoginTracking: .enabled` | Log in | `no usable stored access token` → Facebook UI → `attempting classic login` → `accessTokenLogin: succeeded` | — |
| A2 | No stored token, `prefersLoginTracking: .limited` | Log in | Facebook UI → `attempting limited login` → `identityTokenLogin: succeeded` | — |
| A3 | Classic session, Tracking on | Log in again | **No UI at all.** `storedToken=true, expired=false, trackingForcedToLimited=false` → `attempting silent login` → `silent login succeeded` | — |
| A4 | Classic session, then Tracking **off** | Log in again | `trackingForcedToLimited=true` → `no usable stored access token` → Facebook UI → `attempting limited login` | — |
| A5 | Stored token past its expiry (hard to force, see Notes) | Log in | `expired=true` → `no usable stored access token` → Facebook UI | — |
| A6 | `prefersLoginTracking: .enabled`, Tracking **off** | Log in | `prefersLoginTracking=enabled, suggestedTracking=limited`, and **no** `attempting classic login` line | — |
| B1 | Classic session, then Revoke the grant | Log in again, without logging out first | `⬅️ RESPONSE: 401` → `backend rejected the stored access token` → Facebook consent → second exchange → `accessTokenLogin: succeeded` | ✅ 2026-08-25, device, integ-qa |
| B2 | Backend answering 400 with a decodable error body | Log in with a stored token | Same recovery as B1 | — |
| B3 | Classic session, then network off | Log in again | `silent login failed with a non-recoverable error` → login fails, **no consent screen, and you are still signed in to Facebook** | — |
| B4 | Backend answering 403 (see Notes) | Log in with a stored token | Login fails with no recovery attempt | — |
| C1 | Any interactive login | Dismiss the Facebook dialog | `user cancelled the Facebook login`; the app must treat it as a cancellation, not show an error | — |
| C2 | Hard to force, see Notes | — | `Facebook login failed (…)` carrying Facebook's own message | — |
| C3 | Hard to force, see Notes | — | `Facebook returned neither an access nor an identity token` | — |
| C4 | Classic login whose backend exchange fails while an identity token is available | Log in | `classic login failed, falling back to limited login with the identity token`, then `identityTokenLogin: succeeded` | — |
| D1 | `appSwitch: .enabled`, `prefersLoginTracking: .enabled`, Tracking on, `fbauth2` declared, Facebook app installed and signed in | Log in | `openable Facebook schemes=fbauth2, …`; the Facebook app opens, comes back on its own, exchange succeeds | — |
| D2 | Same as D1, but `appSwitch: .disabled` | Log in | `appSwitch=disabled`; stays in a Safari View Controller, no switch | — |
| D3 | `appSwitch: .enabled`, `prefersLoginTracking: .limited` | Log in | No switch. Expected while the limited-login flag is off, see below | — |
| D4 | Facebook app not installed | Log in | `openable Facebook schemes=none`; browser login whatever `appSwitch` says | — |
| F1 | Limited session | Log in a second time without killing the app | Both succeed, and `logging out of Facebook before a fresh login` appears each time | — |
| F2 | Any session | `logout()`, then log in | Full interactive login, with fresh consent if the grant was revoked | — |
| F3 | Release the `ReachFive` instance while holding on to the provider | Log in | Fails immediately, **before** any Facebook UI opens | — |

## Server-side feature flags

Two of these are off for app `1634029666893228` and cannot be tested until Meta opens them. Check
them before blaming a code change. Read the cached values from the host app:

```swift
let appID = Settings.shared.appID ?? ""
if let data = UserDefaults.standard.data(forKey: "com.facebook.sdk:GateKeepers\(appID)"),
   let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) {
    unarchiver.requiresSecureCoding = false
    let dict = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? [String: Any]
    print(dict?["FBSDKFeatureLimitedLoginRefresh"] ?? "absent", dict?["FBSDKFeatureLimitedLoginFAS"] ?? "absent")
}
```

| Flag | 2026-08-25 | Consequence |
|---|---|---|
| `FBSDKFeatureFBLoginFAS` | 1 | App switch works for classic login (D1) |
| `FBSDKFeatureLimitedLoginFAS` | 0 | No app switch in limited login (D3) |
| `FBSDKFeatureLimitedLoginRefresh` | 0 | The SDK's automatic limited-login refresh never runs |

A missing key reads as off: the default for all three is `false`, and the value comes from a cache
filled asynchronously at app start, so an early read can return the default even when the flag is on.

## Minimum set when bumping the Facebook SDK

A1, A3, B1, C1, D1, D2, F1 — both exchanges, both entry paths, the recovery, a cancellation, and
both app-switch settings.

## Notes

**A4 and A6 regress silently.** Both the silent-path condition and the tracking decision read the
tracking status, and a change to either turns a working login into a rejected token with no crash
and no error until the exchange comes back refused.

**B3 matters as much as B1.** The whole point of narrowing the recovery is that a transient failure
must not log the user out of Facebook and make them consent again. A regression here looks harmless
in a demo and costs a consent screen on every network hiccup in production.

**B4 is a known gap.** A 403 is not reachable on the provider-token route today, but this backend
does answer 403 on other routes, so a refusal of a different nature here would fall outside the
400/401 pair the recovery accepts, and the user would be stuck. Re-check whenever the backend changes.

**C4 is the least exercised path.** Its recovery catches *any* error, so a change to the classic
exchange can silently reroute every classic login into a limited one — with both still returning a
valid token, which is why nothing looks wrong.

**A5, C2 and C3 are hard to force on purpose.** Facebook's long-lived tokens last around 60 days, so
A5 realistically needs a device left alone or a clock change. C2 and C3 depend on Facebook-side
failures. Cover them by reading the log when they happen in the wild rather than by staging them.

**Facebook's automatic limited-login refresh** replaces the stored identity token when the app comes
back to the foreground. It is dormant while its flag is off, and it only acts on an existing limited
session, so it does not interfere with these scenarios today. Worth re-reading this plan if Meta
turns it on.
