# Google Play release kit

Everything needed to publish Pomee (`com.twodesk.pomee`) on Google Play.

| File | Use |
| --- | --- |
| `listing.md` | Store listing text, category and contact details |
| `privacy-policy.md` | Draft of the privacy policy. The live version is https://twodesktech.com/pomee/privacy-policy |
| `icon-512.png` | Hi-res app icon |
| `feature-graphic.png` | Feature graphic |
| `screenshots/` | Phone screenshots |

The graphics are generated from the iOS app icon and `docs/screenshots/`.

## Build the bundle

Play only accepts Android App Bundles. Pushing a `v*.*.*` tag builds a signed
`.aab` and attaches it to the GitHub Release. To build one locally:

```sh
flutter build appbundle --release
# build/app/outputs/bundle/release/app-release.aab
```

It must be signed with the release key from `android/key.properties`.
Play rejects bundles signed with the debug key.

## First upload checklist

1. Create the app in Play Console: name "Pomee", default language English,
   App, Free.
2. Turn on Play App Signing (the default). Your keystore becomes the upload
   key, so keep it and its passwords backed up. If you lose it, you can ask
   Google to reset the upload key.
3. App content (Policy > App content):
   - Privacy policy: https://twodesktech.com/pomee/privacy-policy (also
     linked from the app's About sheet).
   - Ads: No.
   - App access: All functionality is available without special access.
   - Content rating: fill in the questionnaire. Pomee has no user content,
     violence or purchases, so it should rate Everyone / PEGI 3.
   - Target audience: 13 and over (picking under 13 brings the Families
     policy requirements).
   - Data safety: no data collected, no data shared.
   - Government apps / financial features / health: No.
4. Store listing: copy from `listing.md` and upload the graphics.
5. Create a release on the Internal testing track first and upload the
   `.aab`. New personal developer accounts must run a closed test with at
   least 12 testers for 14 days before production. Organization accounts
   can go straight to production.
6. Promote to Production when ready.

## Every later release

Bump the version with a tag (`git tag v1.0.1 && git push origin v1.0.1`),
then upload the new `.aab` from the GitHub Release to Play Console. The
version code comes from the tag and always increases.

The package name `com.twodesk.pomee` is permanent once the first bundle is
uploaded.
