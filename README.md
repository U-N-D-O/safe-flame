# Safe Flame

Safe Flame is a tiny iPhone candle app: tap the round button to turn on a very dim, slow, irregular torch flicker and loop a quiet fireplace recording. Tap it again to stop.

The fireplace recording is bundled from [OpenGameArt's “Fireplace Sound loop”](https://opengameart.org/content/fireplace-sound-loop) under CC0 1.0. The app uses iOS background audio so the fireplace sound may continue when the screen is locked. iOS can suspend torch updates after locking, so the flicker is most reliable while the app remains visible; the app also prevents automatic screen lock while running.

## Unsigned IPA

The GitHub Actions workflow installs XcodeGen, generates `files/SafeFlame.xcodeproj`, builds an unsigned device app, packages `SafeFlame-unsigned.ipa`, and publishes the artifact for AltServer or AltStore.
