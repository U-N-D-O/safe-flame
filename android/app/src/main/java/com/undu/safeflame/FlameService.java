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

    private final Runnable flicker = new Runnable() {
        @Override
        public void run() {
            if (!running) {
                return;
            }
            boolean gust = random.nextDouble() < (mode == 1 ? 0.12 : 0.055);
            float level = mode == 2
                    ? randomBetween(0.30f, 0.48f)
                    : randomBetween(gust ? 0.22f : 0.30f, gust ? 0.58f : 0.52f);
            setTorch(level);
            long delay = mode == 2
                    ? randomBetweenLong(1200, 2600)
                    : mode == 1 ? randomBetweenLong(450, 1500) : randomBetweenLong(350, 1150);
            handler.postDelayed(this, delay);
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
        findTorchCamera();
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
        setTorch(mode == 2 ? 0.38f : 0.42f);
        handler.post(flicker);
        return START_STICKY;
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
            android.content.res.AssetFileDescriptor descriptor = getAssets().openFd(fileName);
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

    private float randomBetween(float minimum, float maximum) {
        return minimum + random.nextFloat() * (maximum - minimum);
    }

    private long randomBetweenLong(long minimum, long maximum) {
        return minimum + (long) (random.nextDouble() * (maximum - minimum));
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
