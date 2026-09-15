package com.undu.safeflame;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.hardware.camera2.CameraCharacteristics;
import android.hardware.camera2.CameraManager;
import android.media.MediaPlayer;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.PowerManager;
import android.os.SystemClock;

import java.io.IOException;
import java.util.Random;

public final class FlameService extends Service {
    public static final String ACTION_START = "com.undu.safeflame.action.START";
    public static final String ACTION_STOP = "com.undu.safeflame.action.STOP";
    public static final String EXTRA_MODE = "mode";

    private static final String CHANNEL_ID = "safe_flame_running";
    private static final int NOTIFICATION_ID = 1001;

    private final Handler handler = new Handler(Looper.getMainLooper());
    private final Random random = new Random();
    private CameraManager cameraManager;
    private String cameraId;
    private int maximumTorchStrength = 1;
    private MediaPlayer audioPlayer;
    private PowerManager.WakeLock wakeLock;
    private int mode;
    private boolean running;
    private double lastMotionTime;
    private double torchLevel;
    private FlameEventMotion flameMotion = new FlameEventMotion(0);

    private final Runnable flicker = new Runnable() {
        @Override
        public void run() {
            if (!running) {
                return;
            }
            double now = SystemClock.elapsedRealtime() / 1000.0;
            double delta = Math.min(0.1, Math.max(1.0 / 120.0, now - lastMotionTime));
            lastMotionTime = now;
            double base = mode == 2 ? 0.312 : 0.320;
            double minimum = (mode == 2 ? 0.30 : 0.22) * 0.8;
            double maximum = (mode == 2 ? 0.48 : 0.58) * 0.8;
            torchLevel = Math.max(minimum, Math.min(maximum, base + flameMotion.value(delta)));
            setTorch((float) torchLevel);
            handler.postDelayed(this, 16L);
        }
    };

    @Override
    public void onCreate() {
        super.onCreate();
        cameraManager = (CameraManager) getSystemService(CAMERA_SERVICE);
        PowerManager powerManager = (PowerManager) getSystemService(POWER_SERVICE);
        if (powerManager != null) {
            wakeLock = powerManager.newWakeLock(
                    PowerManager.PARTIAL_WAKE_LOCK,
                    "SafeFlame::Flicker");
            wakeLock.setReferenceCounted(false);
        }
        mode = getSharedPreferences("safe_flame_state", MODE_PRIVATE)
                .getInt("mode", 0);
        // The Android emulator exposes a software camera/torch that can hang
        // System UI when it is toggled repeatedly. Real devices still use the
        // camera torch normally; the emulator is only used for review capture.
        if (!isEmulator()) {
            findTorchCamera();
        }
        createNotificationChannel();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent != null && ACTION_STOP.equals(intent.getAction())) {
            stopRunning();
            return START_NOT_STICKY;
        }

        if (intent != null && intent.hasExtra(EXTRA_MODE)) {
            mode = intent.getIntExtra(EXTRA_MODE, mode);
            getSharedPreferences("safe_flame_state", MODE_PRIVATE)
                    .edit()
                    .putInt("mode", mode)
                    .apply();
        }
        startForegroundSafely();
        if (wakeLock != null && !wakeLock.isHeld()) {
            wakeLock.acquire();
        }
        running = true;
        getSharedPreferences("safe_flame_state", MODE_PRIVATE)
                .edit()
                .putBoolean("running", true)
                .apply();
        startAudio();
        handler.removeCallbacks(flicker);
        lastMotionTime = SystemClock.elapsedRealtime() / 1000.0;
        flameMotion = new FlameEventMotion(mode);
        torchLevel = initialLevel();
        setTorch((float) torchLevel);
        handler.post(flicker);
        return START_STICKY;
    }

    private float initialLevel() {
        return mode == 2 ? 0.312f : 0.320f;
    }

    private void startForegroundSafely() {
        Notification notification = new Notification.Builder(this, CHANNEL_ID)
                .setContentTitle("Safe Flame is running")
                .setContentText("Soft light and sound are playing")
                .setSmallIcon(android.R.drawable.ic_lock_idle_charging)
                .setOngoing(true)
                .build();

        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA |
                            ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
            );
        } else {
            startForeground(NOTIFICATION_ID, notification);
        }
    }

    private void findTorchCamera() {
        if (cameraManager == null) {
            return;
        }
        try {
            for (String id : cameraManager.getCameraIdList()) {
                CameraCharacteristics characteristics = cameraManager.getCameraCharacteristics(id);
                Boolean hasFlash = characteristics.get(CameraCharacteristics.FLASH_INFO_AVAILABLE);
                if (Boolean.TRUE.equals(hasFlash)) {
                    cameraId = id;
                    if (Build.VERSION.SDK_INT >= 33) {
                        Integer maximum = characteristics.get(
                                CameraCharacteristics.FLASH_INFO_STRENGTH_MAXIMUM_LEVEL);
                        if (maximum != null) {
                            maximumTorchStrength = Math.max(1, maximum);
                        }
                    }
                    return;
                }
            }
        } catch (Exception ignored) {
            cameraId = null;
        }
    }

    private void setTorch(float level) {
        if (isEmulator()) {
            return;
        }
        if (cameraManager == null || cameraId == null) {
            return;
        }
        try {
            if (Build.VERSION.SDK_INT >= 33) {
                int strength = Math.max(1, Math.min(
                        maximumTorchStrength,
                        Math.round(level * maximumTorchStrength)));
                cameraManager.turnOnTorchWithStrengthLevel(cameraId, strength);
            } else {
                cameraManager.setTorchMode(cameraId, level > 0.16f);
            }
        } catch (Exception ignored) {
            // Some devices temporarily make the torch unavailable when warm.
        }
    }

    private void turnTorchOff() {
        if (isEmulator()) {
            return;
        }
        if (cameraManager == null || cameraId == null) {
            return;
        }
        try {
            cameraManager.setTorchMode(cameraId, false);
        } catch (Exception ignored) {
            // Nothing else is needed if the camera is already unavailable.
        }
    }

    private void startAudio() {
        stopAudio();
        String fileName = mode == 1 ? "candle.wav" : mode == 2 ? "nightlight.wav" : "fireplace.wav";
        try {
            android.content.res.AssetFileDescriptor descriptor = getAssets().openFd(
                    "flutter_assets/files/SafeFlame/Resources/" + fileName);
            MediaPlayer player = new MediaPlayer();
            player.setWakeMode(getApplicationContext(), PowerManager.PARTIAL_WAKE_LOCK);
            player.setDataSource(descriptor.getFileDescriptor(), descriptor.getStartOffset(), descriptor.getLength());
            descriptor.close();
            player.setLooping(true);
            float volume = mode == 0 ? 0.34f : mode == 1 ? 0.18f : 0.16f;
            player.setVolume(volume, volume);
            player.prepare();
            player.start();
            audioPlayer = player;
        } catch (IOException | RuntimeException ignored) {
            audioPlayer = null;
        }
    }

    private void stopAudio() {
        if (audioPlayer == null) {
            return;
        }
        try {
            audioPlayer.stop();
        } catch (RuntimeException ignored) {
            // The player may already have reached an error state.
        }
        audioPlayer.release();
        audioPlayer = null;
    }

    private void stopRunning() {
        running = false;
        getSharedPreferences("safe_flame_state", MODE_PRIVATE)
                .edit()
                .putBoolean("running", false)
                .apply();
        handler.removeCallbacks(flicker);
        turnTorchOff();
        stopAudio();
        if (wakeLock != null && wakeLock.isHeld()) {
            wakeLock.release();
        }
        stopForeground(STOP_FOREGROUND_REMOVE);
        stopSelf();
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT < 26) {
            return;
        }
        NotificationChannel channel = new NotificationChannel(
                CHANNEL_ID,
                "Safe Flame",
                NotificationManager.IMPORTANCE_LOW);
        channel.setDescription("Keeps Safe Flame running in the background");
        NotificationManager manager = getSystemService(NotificationManager.class);
        if (manager != null) {
            manager.createNotificationChannel(channel);
        }
    }

    private boolean isEmulator() {
        return Build.FINGERPRINT.startsWith("generic")
                || Build.FINGERPRINT.startsWith("unknown")
                || Build.MODEL.contains("google_sdk")
                || Build.MODEL.contains("Emulator")
                || Build.MODEL.contains("Android SDK built for x86")
                || Build.MANUFACTURER.contains("Genymotion")
                || Build.BRAND.startsWith("generic") && Build.DEVICE.startsWith("generic");
    }

    private final class FlameEventMotion {
        private final double eventMin;
        private final double eventMax;
        private final double recovery;
        private final double regularKick;
        private final double rareKick;
        private final double rareMin;
        private final double rareMax;
        private final double maximumOffset;
        private double time;
        private double nextEvent;
        private double nextRareEvent;
        private double desiredOffset;
        private double currentOffset;
        private double currentVelocity;

        FlameEventMotion(int mode) {
            if (mode == 1) {
                eventMin = 0.55; eventMax = 1.80; recovery = 0.34;
                regularKick = 0.003; rareKick = 0.012;
                rareMin = 4.0; rareMax = 9.0; maximumOffset = 0.144;
            } else if (mode == 2) {
                eventMin = 1.40; eventMax = 3.20; recovery = 0.70;
                regularKick = 0.0015; rareKick = 0.004;
                rareMin = 8.0; rareMax = 16.0; maximumOffset = 0.072;
            } else {
                eventMin = 0.22; eventMax = 0.75; recovery = 0.78;
                regularKick = 0.008; rareKick = 0.020;
                rareMin = 1.8; rareMax = 4.8; maximumOffset = 0.144;
            }
            nextEvent = randomBetween(eventMin, eventMax);
            nextRareEvent = randomBetween(rareMin, rareMax);
        }

        double value(double delta) {
            time += delta;
            if (time >= nextEvent) {
                desiredOffset += randomBetween(-regularKick, regularKick);
                nextEvent = time + randomBetween(eventMin, eventMax);
            }
            if (time >= nextRareEvent) {
                desiredOffset += randomBetween(-rareKick, rareKick);
                nextRareEvent = time + randomBetween(rareMin, rareMax);
            }
            desiredOffset *= Math.exp(-delta / recovery);
            double acceleration = (desiredOffset - currentOffset) * 18.0 - currentVelocity * 8.0;
            currentVelocity += acceleration * delta;
            currentOffset += currentVelocity * delta;
            currentOffset = Math.max(-maximumOffset, Math.min(maximumOffset, currentOffset));
            return currentOffset;
        }

        private double randomBetween(double minimum, double maximum) {
            return minimum + random.nextDouble() * (maximum - minimum);
        }
    }

    @Override
    public void onDestroy() {
        stopRunning();
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
