# Release checklist — Ayat Studio

Everything below is either already automated in `.github/workflows/build-apk.yml`
or is a one-time account setup that no amount of code can do for you. The
one-time items are marked **[manual]**.

## Version

`pubspec.yaml`'s `version: x.y.z+n` is the single source of truth:

* `x.y.z` → Play Console's **versionName** (what users see)
* `+n` → **versionCode**, which must strictly increase on every upload Play
  accepts. Reusing one is rejected outright.

`lib/app_info.dart` carries the same numbers for the in-app Settings screen.
`test/app_info_test.dart` fails the build if the two ever disagree, so bump
both together.

Current: **1.1.0+2**.

## What CI produces

Pushing to `main` or any `claude/**` branch runs the workflow, which:

1. Re-hosts the Whisper GGML models on this repo's `models` release (the app
   downloads them from github.com on first use — see `whisper_service.dart`
   for why not from Hugging Face directly).
2. Generates the `android/` folder, pins compileSdk 36 / minSdk 24 / NDK
   29.0.13113456, and adds the INTERNET + RECORD_AUDIO permissions and the
   Arabic app label to the manifest.
3. Runs `flutter test` and the ayah-detection accuracy gate
   (`dart run tool/matcher_bench.dart 300`), which fails the build below 90%
   top-1 or on any false positive.
4. Builds **both** artifacts:
   * `app-release.apk` — for Telegram / APKPure / Uptodown sideloading
   * `app-release.aab` — the App Bundle Play Console requires for new apps

Download them from the run's **Artifacts** section.

## Signing **[manual]**

Play requires every upload to be signed with the same key. Until these four
repository secrets exist, CI silently falls back to the debug key, which
Play Console will reject and which makes in-place updates impossible:

| Secret | What it is |
| --- | --- |
| `RELEASE_KEYSTORE_BASE64` | `base64 -w0 release-keystore.jks` |
| `RELEASE_KEYSTORE_PASSWORD` | keystore password |
| `RELEASE_KEY_ALIAS` | key alias inside the keystore |
| `RELEASE_KEY_PASSWORD` | key password |

Create the keystore once and back it up somewhere you will still have in five
years — losing it means never being able to update the listing again:

```
keytool -genkey -v -keystore release-keystore.jks -keyalg RSA \
        -keysize 2048 -validity 10000 -alias ayat-studio
```

## Play Console data safety **[manual]**

The form asks what leaves the device. For this app the honest answers are:

* **No data collected, no data shared.** There is no account, no analytics
  SDK, no ad SDK, and no crash reporter.
* Audio is transcribed **entirely on-device** by the bundled Whisper model.
  No recording is uploaded, for that or anything else.
* Three outbound requests exist, all of them either user-initiated or
  one-time, and none of them carrying anything about the user:
  1. the one-time Whisper model download (github.com)
  2. tafsir text for an ayah the user opened — carries only surah number,
     ayah number and which tafsir was chosen (jsDelivr / raw.githubusercontent)
  3. optional AI background generation — carries only a short scene
     description derived from the ayah (Pollinations AI)
* Google Fonts are fetched at runtime by the `google_fonts` package.

`docs/privacy-policy.html` says all of this in Arabic and English; publish it
(GitHub Pages serves `docs/`) and paste the URL into the listing. It is also
shown in the app's Settings screen.

## Content rating **[manual]**

Religious reference/reading app with a video editor. No user-generated public
content, no chat, no purchases, no ads. The IARC questionnaire should come out
at "Everyone".

## Before each upload

- [ ] `flutter analyze` clean
- [ ] `flutter test` green
- [ ] `dart run tool/matcher_bench.dart 300` prints `OK`
- [ ] version bumped in `pubspec.yaml` **and** `lib/app_info.dart`
- [ ] privacy policy's "last updated" date reflects any new network use
- [ ] the `models` release still has all five `.bin` assets attached
      (`ggml-quran-lora-base.bin` needs the separate
      `prepare-quran-model.yml` workflow run once; without it the دقة القرآن
      tier falls back to `small` at runtime rather than failing)
