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
    private double motionStartedAt;
    private double lastMotionTime;
    private double torchLevel;
    private double torchVelocity;
    private FlameDrift quickMotion = new FlameDrift(0.35);
    private FlameDrift bodyMotion = new FlameDrift(1.3);
    private FlameDrift slowMotion = new FlameDrift(4.7);

    private final Runnable flicker = new Runnable() {
        @Override
        public void run() {
            if (!running) {
                return;
            }
            double now = SystemClock.elapsedRealtime() / 1000.0;
            double elapsed = now - motionStartedAt;
            double delta = Math.min(0.1, Math.max(1.0 / 120.0, now - lastMotionTime));
            lastMotionTime = now;

            double quickWeight;
            double bodyWeight;
            double slowWeight;
            if (mode == 1) {
                quickWeight = 0.10;
                bodyWeight = 0.55;
                slowWeight = 0.35;
            } else if (mode == 2) {
                quickWeight = 0.05;
                bodyWeight = 0.25;
                slowWeight = 0.70;
            } else {
                quickWeight = 0.25;
                bodyWeight = 0.60;
                slowWeight = 0.15;
            }
            double noise = Math.tanh(1.8 * (quickWeight * quickMotion.value(elapsed)
                    + bodyWeight * bodyMotion.value(elapsed)
                    + slowWeight * slowMotion.value(elapsed)));
            double minimum = (mode == 2 ? 0.30 : 0.22) * 0.8;
            double maximum = (mode == 2 ? 0.48 : 0.58) * 0.8;
            double target = minimum + (maximum - minimum) * (0.5 + 0.5 * noise);

            // Mean-reverting movement avoids held high/low targets while
            // remaining smooth between every 60 Hz torch update.
            double response = mode == 2 ? 0.45 : mode == 1 ? 0.95 : 1.35;
            double damping = mode == 2 ? 1.25 : mode == 1 ? 1.65 : 1.95;
            double acceleration = (target - torchLevel) * response - torchVelocity * damping;
            torchVelocity += acceleration * delta;
            torchLevel += torchVelocity * delta;
            torchLevel = Math.max(minimum, Math.min(maximum, torchLevel));
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
        motionStartedAt = SystemClock.elapsedRealtime() / 1000.0;
        lastMotionTime = motionStartedAt;
        torchLevel = initialLevel();
        torchVelocity = 0;
        bodyMotion = new FlameDrift(mode == 1 ? 2.0 : 1.3);
        slowMotion = new FlameDrift(mode == 1 ? 5.3 : 4.7);
        quickMotion = new FlameDrift(mode == 1 ? 0.65 : mode == 2 ? 1.8 : 0.35);
        setTorch((float) torchLevel);
        handler.post(flicker);
        return START_STICKY;
    }

    private float initialLevel() {
        return (mode == 2 ? 0.38f : 0.42f) * 0.8f;
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

    // Same cubic B-spline noise as iOS: continuous value, velocity and
    // acceleration across random control points, with no stops at knots.
    private final class FlameDrift {
        private final double interval;
        private int segment;
        private final double[] points = new double[4];

        FlameDrift(double interval) {
            this.interval = interval;
            for (int i = 0; i < points.length; i++) points[i] = random.nextDouble() * 2 - 1;
        }

        double value(double time) {
            double position = Math.max(0, time) / interval;
            int nextSegment = (int) position;
            while (segment < nextSegment) {
                System.arraycopy(points, 1, points, 0, 3);
                points[3] = random.nextDouble() * 2 - 1;
                segment++;
            }
            double u = position - segment;
            double u2 = u * u;
            double u3 = u2 * u;
            return (Math.pow(1 - u, 3) * points[0]
                    + (3 * u3 - 6 * u2 + 4) * points[1]
                    + (-3 * u3 + 3 * u2 + 3 * u + 1) * points[2]
                    + u3 * points[3]) / 6;
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
