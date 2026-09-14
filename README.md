# Safe Flame

Safe Flame is a gentle phone companion for safe rest, calmness, and peaceful nights. It uses the phone's flashlight to create a soft, candle-like glow and plays quiet ambient sound in a loop.

It is made for anyone who wants a controllable nighttime light without a real flame: children who sleep better with a light, couples settling down together, people who find familiar light and sound comforting, and anyone looking for a calmer bedtime atmosphere.

Safe Flame is made by **QILA Modus**.

## Features

- Fireplace, Candle, and Moonlight modes.
- Soft, randomized flashlight flicker designed to feel natural rather than mechanical.
- A matching ambient sound for each mode, played continuously.
- Simple left and right mode controls with one central start/stop button.
- An in-app sleep dimmer that hides the controls and can be dismissed with a tap or swipe.
- Shared Flutter interface and behavior for Android phones and iPhones.
- No real fire and no camera features.

### Android flashlight note

Android exposes flashlight control through its camera hardware APIs. Safe Flame uses that access only to control the flashlight; it does not open the camera, take photos, or record video. Android also uses a foreground service so the sound and flashlight can continue while the app is minimized or the screen is locked on supported devices.

The Android emulator can demonstrate the app interface, sound, and background service, but it has no physical flashlight LED.

### iPhone note

iPhone hardware and iOS background rules may limit flashlight and audio behavior when the device is locked or the app is suspended. The in-app sleep dimmer is available for a screen-darkened bedtime experience while Safe Flame remains open.

## Project layout

The shared Flutter app is at the repository root. Android and iOS native code only provide the platform-specific flashlight, audio, and background-service bridges.

```text
lib/                         Shared Flutter interface
files/SafeFlame/Resources/   Icons and ambient audio
android/                     Android project and foreground service
ios/                         iOS project and flashlight/audio bridge
.github/workflows/           Android and iOS build workflows
```

## Run locally

Install Flutter, then run:

```bash
flutter pub get
flutter run
```

For iOS, use a Mac with Xcode. For Android, use Android Studio or an Android device/emulator.

## Build releases

Android App Bundle for Google Play:

```bash
flutter build appbundle --release
```

Unsigned iOS build for AltServer/AltStore packaging:

```bash
flutter build ios --release --no-codesign
```

The GitHub Actions workflows build the Android App Bundle and unsigned iOS IPA from this same shared project. Android release signing is supplied through workflow secrets/environment variables; signing passwords and keystores do not belong in the repository.

## License and audio

The bundled fireplace recording is identified in `files/SafeFlame/Resources/CC0-NOTICE.txt`. Other bundled sounds and artwork are project assets.
