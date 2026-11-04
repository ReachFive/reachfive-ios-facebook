# Manual test plan

`ConfiguredFacebookProvider.login` picks between two exchanges, recovers from a rejected token,
and hands off to the Facebook app or to a browser. None of it is covered by automated tests:
every branch needs a real Facebook session or a real tracking status.
Walk this list when changing the provider or bumping the Facebook SDK.

## Reading the log

Use the debug/logs branch to have the provider print debug information.
Build the host app with `SdkInternalConfig(loggingEnabled: true)` as well, to get the `➡️ REQUEST` / `⬅️ RESPONSE`
pairs with statuses and bodies.

Telling the two exchanges apart on the wire:

- **Classic** — a single `POST /identity/v1/oauth/provider/token`.
- **Limited** — `GET /oauth/authorize`, a 302 whose `Location` carries the code, then `POST /oauth/token`.

## State axes

| Axis | Values | Read by |
|---|---|---|
| `prefersLoginTracking` | `.enabled` · `.limited` (default) | the provider — picks the exchange |
| App Tracking Transparency | authorized · anything else | the provider — overrides `prefersLoginTracking` |
| Stored access token | absent · valid · expired · revoked server-side | the provider — decides the silent path |
| `appSwitch` | `.enabled` (default) · `.disabled` | forwarded as-is, the provider decides nothing |
| `fbauth2` in `Info.plist` | declared · absent | the Facebook SDK |
| Facebook app | absent · installed, signed out · installed, signed in | the Facebook SDK |
| facebook.com in the browser | signed in · signed out | Facebook's web page |

Only the first three change what our code does — **Part 1** covers them. The last four change how
Facebook presents the login, with our code taking the same path throughout; **Part 2** covers them
once, instead of multiplying them across every scenario.

## Set-up recipes

The Set up columns refer to these by name.

**Tracking on / off** — Settings › Privacy & Security › Tracking › (the app). Toggling it there
takes effect without reinstalling (or not — check the `trackingForcedToLimited:` line to be sure).

**Classic session** — build with `prefersLoginTracking: .enabled`, Tracking on, log in once.
Leaves a stored access token behind.

**Limited session** — build with `prefersLoginTracking: .limited` (the default), log in once.
Leaves no access token behind, which is why the silent path never runs afterwards.

**No stored token** — call `logout()`, or reinstall. Nothing else clears it: no Graph API failure
does, so a revoked token stays in place until the next interactive login.

**Revoke the grant** — take the `provider_token` from the request body of the last classic exchange:

```sh
FB_TOKEN=the_token
curl -s -X DELETE "https://graph.facebook.com/v21.0/me/permissions" -H "Authorization: Bearer $FB_TOKEN"
curl -s "https://graph.facebook.com/v21.0/me?fields=id" -H "Authorization: Bearer $FB_TOKEN"
```

The second call must fail with code `190` (subcode `458` or `467`). If it still returns an id, the
revocation did not apply.

**Inspect a token** — when a call does not do what you expect, check who the token actually belongs
to before blaming the code. `data.app_id` must be `1634029666893228`, and `data.is_valid` tells you
whether a revocation went through:

```sh
curl -s "https://graph.facebook.com/v21.0/debug_token?input_token=$FB_TOKEN&access_token=$FB_TOKEN" | jq .data
```

The `access_token` parameter has to belong to a developer of the application — yours does. An app
token (`APP_ID|APP_SECRET`) works too, if you have the secret at hand.

> Revoking de-authorizes the app entirely. The next login only re-requests the scopes the provider
> configuration lists, so anything granted beyond that set is lost for that user.

---

# Part 1 — Paths through the provider

Run these on any change to the provider. Each section fixes the provider configuration and the
tracking status, then varies the token state.

## 1.1 Classic exchange — `prefersLoginTracking: .enabled`, Tracking on

| # | Set up | Run | Observe |
|---|---|---|---|
| 1.1.a | No stored token | Log in | `no usable stored access token` → Facebook login → `attempting classic login` → `accessTokenLogin: succeeded` |
| 1.1.b | Classic session | Log in again | **No UI at all.** `storedToken=true, expired=false, trackingForcedToLimited=false` → `attempting silent login` → `silent login succeeded` |
| 1.1.c | Stored token past its expiry (see Notes) | Log in | `expired=true` → `no usable stored access token` → Facebook login |
| 1.1.d | Any interactive login above | Dismiss the Facebook dialog | `user cancelled the Facebook login`, treated as a cancellation and not as an error |

## 1.2 Tracking overrides the preference — `prefersLoginTracking: .enabled`, Tracking off

| # | Set up | Run | Observe |
|---|---|---|---|
| 1.2.a | No stored token | Log in | `trackingForcedToLimited=true`, `prefersLoginTracking=enabled, suggestedTracking=limited`, **no** `attempting classic login` line → `attempting limited login` → `identityTokenLogin: succeeded` |
| 1.2.b | Classic session, then Tracking **off** | Log in again | The silent path is skipped even though the token is valid: `trackingForcedToLimited=true` → `no usable stored access token` → Facebook login → limited exchange |

## 1.3 Limited exchange — `prefersLoginTracking: .limited`

| # | Set up | Run | Observe |
|---|---|---|---|
| 1.3.a | No stored token, Tracking on | Log in | `suggestedTracking=limited` even with Tracking on → `attempting limited login` → `identityTokenLogin: succeeded` |
| 1.3.b | Limited session, app **not** killed since | Log in a second time | Both succeed, and `logging out of Facebook before a fresh login` appears each time |

## 1.4 Recovering from a rejected stored token

| # | Set up | Run | Observe |
|---|---|---|---|
| 1.4.a | Classic session, then Revoke the grant | Log in again, without logging out first | `⬅️ RESPONSE: 401` → `backend rejected the stored access token` → Facebook consent → second exchange → `accessTokenLogin: succeeded` |
| 1.4.b | Classic session, then network off | Log in again | `silent login failed with a non-recoverable error` → the login fails, **no consent screen, and you are still signed in to Facebook** |
| 1.4.c | Classic login whose backend exchange fails while an identity token is available | Log in | `classic login failed, falling back to limited login with the identity token` → `identityTokenLogin: succeeded` |

## 1.5 Lifetimes

| # | Set up | Run | Observe |
|---|---|---|---|
| 1.5.a | Any session | `logout()`, then log in | Full interactive login, with fresh consent if the grant was revoked |
| 1.5.b | Release the `ReachFive` instance while holding on to the provider | Log in | Fails immediately, **before** any Facebook UI opens |

---

# Part 2 — How Facebook presents the login

**Every row here runs the same provider code as 1.1.a**, except 2.h which is called out below. What
changes is Facebook's own choice of surface, decided inside its SDK from the scheme, the installed
app and the browser session. Run this part when bumping the Facebook SDK or when touching
`appSwitch` or `fbauth2`; skip it when you change provider logic only.

There are **two different ways to end up in the Facebook app**, and they are not the same feature:

- a **direct switch**, with no web page opening at all — this is Fast App Switch;
- a **browser page that offers to open the app**, which Facebook shows when the user is not signed
  in on the web, whatever `appSwitch` says.

The Sandbox declares `fbauth2`; remove the line from its `Info.plist` to test the rows that need it
absent.

| # | `appSwitch` | `fbauth2` | Facebook app | facebook.com | Observe |
|---|---|---|---|---|---|
| 2.a | `.enabled` | declared | installed, signed in | any | `openable Facebook schemes=fbauth2, …` → direct switch to the Facebook app, **no web page at all**, returns on its own |
| 2.b | `.enabled` | declared | installed, signed **out** | any | Not yet observed — record what happens and fill this row in |
| 2.c | `.enabled` | declared | absent | signed in | `openable Facebook schemes=none` → browser, consent on an already-authenticated account |
| 2.d | `.enabled` | declared | absent | signed out | `openable Facebook schemes=none` → browser, login form |
| 2.e | `.enabled` | **removed** | installed, signed in | any | `openable Facebook schemes=none` → browser: without the scheme the SDK cannot see the app |
| 2.f | `.disabled` | declared | installed, signed in | signed **out** | `appSwitch=disabled` → browser, and Facebook's page offers to open the app, **every single time** |
| 2.g | `.disabled` | declared | installed, signed in | signed in | `appSwitch=disabled` → browser, and no prompt to open the app |
| 2.h | `.enabled` | declared | installed, signed in | any | With `prefersLoginTracking: .limited`: no switch at all, limited login stays in the browser while `FBSDKFeatureLimitedLoginFAS` is off |

2.h is the only row that changes a provider input, and the only one whose outcome depends on a
server-side flag rather than on the device.

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
| `FBSDKFeatureFBLoginFAS` | 1 | The direct switch works for classic login (2.a) |
| `FBSDKFeatureLimitedLoginFAS` | 0 | No direct switch in limited login (2.h) |
| `FBSDKFeatureLimitedLoginRefresh` | 0 | The SDK's automatic limited-login refresh never runs |

A missing key reads as off: the default for all three is `false`, and the value comes from a cache
filled asynchronously at app start, so an early read can return the default even when the flag is on.

---

## Minimum set when bumping the Facebook SDK

1.1.a, 1.1.b, 1.3.a, 1.4.a, 1.1.d, 2.a, 2.f — both exchanges, the silent path, the recovery,
a cancellation, and both ways of reaching the Facebook app.

## Notes

**1.2.b and 1.2.a regress silently.** Both the silent-path condition and the tracking decision read
the tracking status, and a change to either turns a working login into a rejected token, with no
crash and no error until the exchange comes back refused.

**1.4.b matters as much as 1.4.a.** The whole point of narrowing the recovery is that a transient
failure must not log the user out of Facebook and make them consent again. A regression here looks
harmless in a demo and costs a consent screen on every network hiccup in production.

**1.4.c is the least exercised path.** Its recovery catches *any* error, so a change to the classic
exchange can silently reroute every classic login into a limited one — both still return a valid
token, which is why nothing looks wrong.

**A backend refusal that is neither 400 nor 401 leaves the user stuck.** It is not reachable on the
provider-token route today, but this backend does answer 403 on other routes, so a refusal of a
different nature here would fall outside the pair the recovery accepts. Re-check whenever the
backend changes.

**1.1.c is hard to force.** Facebook's long-lived tokens last around 60 days, so it realistically
needs a device left alone or a clock change.

**Two failures you cannot stage, only recognise.** `Facebook login failed (…)`, carrying Facebook's
own message, and `Facebook returned neither an access nor an identity token`. Both depend on a
Facebook-side failure. There is nothing to run for them — know the two lines so you recognise them
when they show up in a log, rather than staging them.

**Facebook's automatic limited-login refresh** replaces the stored identity token when the app comes
back to the foreground. It is dormant while its flag is off, and it only acts on an existing limited
session, so it does not interfere with these scenarios today. Worth re-reading this plan if Meta
turns it on.
