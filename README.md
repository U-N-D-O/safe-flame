# Safe Flame

Safe Flame is a tiny iPhone night-light app: tap the round button to turn on a very dim, irregular torch flicker and loop a quiet sound. Use the small arrows to switch between Fireplace, Candle, and Moonlight moods. Tap the round button again to stop. The app icon and logo are the warm flame mark in `files/SafeFlame/Assets.xcassets`.

The fireplace recording is bundled from [OpenGameArt's “Fireplace Sound loop”](https://opengameart.org/content/fireplace-sound-loop) under CC0 1.0. The app uses iOS background audio so the fireplace sound may continue when the screen is locked. iOS can suspend torch updates after locking, so the flicker is most reliable while the app remains visible; the app also prevents automatic screen lock while running.

The small lock button is a sleep dimmer: it lowers the display to nearly black while leaving the flame and sound running, and tapping anywhere wakes the display and restores its previous brightness. A real locked or powered-off iPhone display cannot receive touch events from a third-party app, and iOS may suspend camera/torch control when the app is actually backgrounded.

The flicker controller uses an original Swift implementation of a smoothed random walk with occasional air-pulse events. It follows the general approach used by open-source LED projects such as [JLED](https://github.com/jandelgado/jled) and [flickering-flame](https://github.com/micromouseonline/flickering-flame), without copying their Arduino code.

## Unsigned IPA

The GitHub Actions workflow installs XcodeGen, generates `files/SafeFlame.xcodeproj`, builds an unsigned device app, packages `SafeFlame-unsigned.ipa`, and publishes the artifact for AltServer or AltStore.
