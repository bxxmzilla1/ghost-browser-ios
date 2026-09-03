# GhostTweak

Blaze-style sideload tweak for Instagram: device ID spoofing (IDFA/IDFV), request header injection (Authorization, X-MID, IG-U-DS-USER-ID, …), and **login cookie injection** from a pasted token block.

Works alongside or instead of BlazeUniversal — it is a separate `GhostTweak.dylib` loaded into the Instagram app bundle.

## Build (macOS / GitHub Actions)

```bash
cd GhostTweak && make
```

Produces `GhostTweak.dylib` (arm64, unsigned).

## Patch Instagram.ipa (Windows or macOS)

```bash
pip install lief
python scripts/patch_instagram.py "IG IPA/Instagram.ipa" GhostTweak/GhostTweak.dylib "IG IPA/Instagram-Ghost.ipa"
```

This copies the dylib into `Frameworks/` and adds an `LC_LOAD_DYLIB` load command to the Instagram binary. Your existing `Sideloadbypass2.dylib` / Blaze / Substrate files are left untouched.

## Sideload

1. Sideload `Instagram-Ghost.ipa` with Sideloadly (same Apple ID as GhostBrowser).
2. Launch Instagram → **3-finger double-tap** anywhere → **Ghost Tweak** settings.

## Import login (GhostBrowser → native Instagram)

1. In GhostBrowser, log into instagram.com in a session.
2. Identity menu → **Instagram bridge…** → **Copy token block**.
3. Open sideloaded Instagram → 3-finger double-tap → paste in the text field.
4. **Import from paste field** → force-quit Instagram and reopen.

Cookies (`sessionid`, `ds_user_id`, …) are injected into `NSHTTPCookieStorage` and headers are attached to instagram.com requests.

## What it hooks

| Target | Effect |
|--------|--------|
| `NSHTTPCookieStorage` | Injects session cookies on launch / foreground |
| `NSMutableURLRequest` | Adds Authorization, X-MID, IG-U-* on instagram.com |
| `ASIdentifierManager` | Spoofed IDFA |
| `UIDevice identifierForVendor` | Spoofed IDFV |

## Notes

- Not a full Blaze clone (no Matchfix cloud, no GPS spoof UI yet).
- Meta may still reject sessions if device fingerprint mismatches — fill IDFA/IDFV/Android ID in the token block or use **Generate missing device IDs**.
- Repackaging Instagram is for personal sideloading only.
