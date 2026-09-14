# Safe Flame

Safe Flame is made by QILA Modus.

Safe Flame is a tiny iPhone night-light app: tap the round button to turn on a very dim, irregular torch flicker and loop a quiet sound. Use the small arrows to switch between Fireplace, Candle, and Moonlight moods. Tap the round button again to stop. The app icon and logo are the warm flame mark in `files/SafeFlame/Assets.xcassets`.

The fireplace recording is bundled from [OpenGameArt's “Fireplace Sound loop”](https://opengameart.org/content/fireplace-sound-loop) under CC0 1.0. The app uses iOS background audio so the fireplace sound may continue when the screen is locked. iOS can suspend torch updates after locking, so the flicker is most reliable while the app remains visible; the app also prevents automatic screen lock while running.

The small lock button is a sleep dimmer: it lowers the display to nearly black while leaving the flame and sound running, and tapping anywhere wakes the display and restores its previous brightness. A real locked or powered-off iPhone display cannot receive touch events from a third-party app, and iOS may suspend camera/torch control when the app is actually backgrounded.

The flicker controller uses an original Swift implementation of a smoothed random walk with occasional air-pulse events. It follows the general approach used by open-source LED projects such as [JLED](https://github.com/jandelgado/jled) and [flickering-flame](https://github.com/micromouseonline/flickering-flame), without copying their Arduino code.

## Unsigned IPA

The GitHub Actions workflow installs XcodeGen, generates `files/SafeFlame.xcodeproj`, builds an unsigned device app, packages `SafeFlame-unsigned.ipa`, and publishes the artifact for AltServer or AltStore.

## Google Play Android build

The Android port is in `android/`. It uses a foreground service for torch flicker and looping audio, and shares the WAV files from `files/SafeFlame/Resources`. The manual `Build Safe Flame Android` workflow produces a signed Android App Bundle (`.aab`) and the Google Play feature graphic.

Google Play requires new apps to be uploaded as Android App Bundles. The current Play listing feature graphic is `store/google-play/feature-graphic.jpg` at 1024 × 500 pixels, 24-bit RGB JPEG.

Before running the Android workflow, add these repository secrets: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, and `ANDROID_KEY_PASSWORD`. `ANDROID_KEYSTORE_BASE64` is the base64-encoded upload keystore; keep the keystore and passwords private because the same signing identity is needed for future updates.
