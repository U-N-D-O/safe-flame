# Safe Flame

Safe Flame is a tiny iPhone night-light app: tap the round button to turn on a very dim, irregular torch flicker and loop a quiet sound. Use the small arrows to switch between Fireplace, Candle, and Moonlight moods. Tap the round button again to stop.

The fireplace recording is bundled from [OpenGameArt's “Fireplace Sound loop”](https://opengameart.org/content/fireplace-sound-loop) under CC0 1.0. The app uses iOS background audio so the fireplace sound may continue when the screen is locked. iOS can suspend torch updates after locking, so the flicker is most reliable while the app remains visible; the app also prevents automatic screen lock while running.

The flicker controller uses an original Swift implementation of a smoothed random walk with occasional air-pulse events. It follows the general approach used by open-source LED projects such as [JLED](https://github.com/jandelgado/jled) and [flickering-flame](https://github.com/micromouseonline/flickering-flame), without copying their Arduino code.

## Unsigned IPA

The GitHub Actions workflow installs XcodeGen, generates `files/SafeFlame.xcodeproj`, builds an unsigned device app, packages `SafeFlame-unsigned.ipa`, and publishes the artifact for AltServer or AltStore.
