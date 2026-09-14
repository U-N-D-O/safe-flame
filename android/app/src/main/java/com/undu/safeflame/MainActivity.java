package com.undu.safeflame;

import android.Manifest;
import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.PorterDuff;
import android.graphics.RadialGradient;
import android.graphics.Shader;
import android.graphics.drawable.GradientDrawable;
import android.os.Build;
import android.os.Bundle;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.WindowManager;
import android.widget.FrameLayout;
import android.widget.ImageButton;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.Space;
import android.widget.TextView;

public final class MainActivity extends Activity {
    private static final int CAMERA_REQUEST = 10;
    private static final int NOTIFICATION_REQUEST = 11;

    private FrameLayout root;
    private FrameLayout flameButton;
    private TextView modeLabel;
    private ImageButton lockButton;
    private View dimOverlay;
    private boolean running;
    private boolean dimmed;
    private float savedBrightness = -1f;
    private int mode;

    private final String[] modeNames = {"Fireplace", "Candle", "Moonlight"};

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().setStatusBarColor(Color.rgb(3, 10, 24));
        getWindow().setNavigationBarColor(Color.rgb(3, 10, 24));
        buildInterface();

        if (Build.VERSION.SDK_INT >= 33 &&
                checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, NOTIFICATION_REQUEST);
        }
    }

    private void buildInterface() {
        root = new FrameLayout(this);
        root.addView(new NightBackgroundView(), new FrameLayout.LayoutParams(-1, -1));

        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setGravity(Gravity.CENTER_HORIZONTAL);
        content.setPadding(dp(24), dp(12), dp(24), dp(8));
        root.addView(content, new FrameLayout.LayoutParams(-1, -1));

        Space topSpace = new Space(this);
        content.addView(topSpace, new LinearLayout.LayoutParams(1, 0, 1f));

        LinearLayout controls = new LinearLayout(this);
        controls.setGravity(Gravity.CENTER_VERTICAL);
        addArrow(controls, "‹", "Previous mood", -1);
        buildFlameButton();
        controls.addView(flameButton, new LinearLayout.LayoutParams(dp(136), dp(136)));
        addArrow(controls, "›", "Next mood", 1);
        content.addView(controls, new LinearLayout.LayoutParams(-1, dp(156)));

        modeLabel = new TextView(this);
        modeLabel.setGravity(Gravity.CENTER);
        modeLabel.setTextColor(Color.WHITE);
        modeLabel.setTextSize(16);
        modeLabel.setLetterSpacing(0.04f);
        LinearLayout.LayoutParams labelParams = new LinearLayout.LayoutParams(-1, dp(54));
        labelParams.topMargin = dp(8);
        content.addView(modeLabel, labelParams);

        Space bottomSpace = new Space(this);
        content.addView(bottomSpace, new LinearLayout.LayoutParams(1, 0, 1f));

        lockButton = new ImageButton(this);
        lockButton.setImageResource(android.R.drawable.ic_lock_lock);
        lockButton.setColorFilter(Color.WHITE, PorterDuff.Mode.SRC_IN);
        lockButton.setAlpha(0.42f);
        GradientDrawable lockBackground = new GradientDrawable(
                GradientDrawable.Orientation.TL_BR,
                new int[]{Color.rgb(39, 53, 73), Color.rgb(12, 20, 33)});
        lockBackground.setShape(GradientDrawable.OVAL);
        lockBackground.setStroke(dp(1), Color.argb(28, 255, 255, 255));
        lockButton.setBackground(lockBackground);
        lockButton.setElevation(dp(5));
        lockButton.setPadding(dp(12), dp(12), dp(12), dp(12));
        lockButton.setContentDescription("Dim screen");
        lockButton.setOnClickListener(view -> dimScreen());
        LinearLayout.LayoutParams lockParams = new LinearLayout.LayoutParams(dp(48), dp(48));
        lockParams.gravity = Gravity.CENTER_HORIZONTAL;
        lockParams.bottomMargin = dp(8);
        content.addView(lockButton, lockParams);

        dimOverlay = new View(this);
        dimOverlay.setBackgroundColor(Color.BLACK);
        dimOverlay.setVisibility(View.GONE);
        dimOverlay.setClickable(true);
        dimOverlay.setContentDescription("Wake screen");
        dimOverlay.setOnTouchListener((view, event) -> {
            if (event.getActionMasked() == MotionEvent.ACTION_DOWN) {
                wakeScreen();
            }
            return true;
        });
        root.addView(dimOverlay, new FrameLayout.LayoutParams(-1, -1));

        setContentView(root);
        updateModeLabel();
        updateControls();
    }

    private void buildFlameButton() {
        flameButton = new FrameLayout(this);
        GradientDrawable background = new GradientDrawable();
        background.setShape(GradientDrawable.OVAL);
        background.setColors(new int[]{Color.rgb(40, 54, 75), Color.rgb(11, 19, 32)});
        background.setGradientType(GradientDrawable.LINEAR_GRADIENT);
        background.setStroke(dp(1), Color.argb(42, 255, 255, 255));
        flameButton.setBackground(background);
        flameButton.setElevation(dp(12));
        flameButton.setContentDescription("Start Fireplace");
        flameButton.setOnClickListener(view -> toggleRunning());

        ImageView logo = new ImageView(this);
        logo.setImageResource(R.drawable.safe_flame_logo);
        logo.setScaleType(ImageView.ScaleType.CENTER_INSIDE);
        logo.setPadding(dp(25), dp(25), dp(25), dp(25));
        logo.setAlpha(0.94f);
        flameButton.addView(logo, new FrameLayout.LayoutParams(-1, -1));
    }

    private void addArrow(LinearLayout parent, String text, String description, int direction) {
        TextView arrow = new TextView(this);
        arrow.setText(text);
        arrow.setTextColor(Color.argb(150, 255, 255, 255));
        arrow.setTextSize(42);
        arrow.setGravity(Gravity.CENTER);
        arrow.setContentDescription(description);
        arrow.setOnClickListener(view -> changeMode(direction));
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(0, dp(100), 1f);
        parent.addView(arrow, params);
    }

    private void toggleRunning() {
        if (running) {
            stopService(new Intent(this, FlameService.class).setAction(FlameService.ACTION_STOP));
            running = false;
            getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        } else if (checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
            startFlameService();
        } else {
            requestPermissions(new String[]{Manifest.permission.CAMERA}, CAMERA_REQUEST);
        }
        updateControls();
    }

    private void startFlameService() {
        Intent intent = new Intent(this, FlameService.class)
                .setAction(FlameService.ACTION_START)
                .putExtra(FlameService.EXTRA_MODE, mode);
        if (Build.VERSION.SDK_INT >= 26) {
            startForegroundService(intent);
        } else {
            startService(intent);
        }
        running = true;
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        requestNotificationPermissionIfNeeded();
    }

    private void changeMode(int direction) {
        mode = (mode + direction + modeNames.length) % modeNames.length;
        updateModeLabel();
        if (running) {
            startFlameService();
        }
    }

    private void updateModeLabel() {
        modeLabel.setText(running
                ? modeNames[mode] + "  ·  Tap flame to stop"
                : modeNames[mode] + "  ·  Tap flame to start");
        flameButton.setContentDescription(running ? "Stop " + modeNames[mode] : "Start " + modeNames[mode]);
    }

    private void updateControls() {
        lockButton.setVisibility(running ? View.VISIBLE : View.INVISIBLE);
        updateModeLabel();
    }

    private void dimScreen() {
        if (!running || dimmed) {
            return;
        }
        WindowManager.LayoutParams attributes = getWindow().getAttributes();
        savedBrightness = attributes.screenBrightness;
        attributes.screenBrightness = 0.01f;
        getWindow().setAttributes(attributes);
        dimmed = true;
        dimOverlay.setVisibility(View.VISIBLE);
        dimOverlay.bringToFront();
    }

    private void wakeScreen() {
        if (!dimmed) {
            return;
        }
        WindowManager.LayoutParams attributes = getWindow().getAttributes();
        attributes.screenBrightness = savedBrightness;
        getWindow().setAttributes(attributes);
        savedBrightness = -1f;
        dimmed = false;
        dimOverlay.setVisibility(View.GONE);
    }

    @Override
    protected void onPause() {
        // Leaving the app must never leave the system brightness dimmed.
        wakeScreen();
        super.onPause();
    }

    @Override
    protected void onResume() {
        super.onResume();
        boolean serviceRunning = getSharedPreferences("safe_flame_state", MODE_PRIVATE)
                .getBoolean("running", false);
        if (running != serviceRunning) {
            running = serviceRunning;
            updateControls();
        }
    }

    private void requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= 33 &&
                checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, NOTIFICATION_REQUEST);
        }
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == CAMERA_REQUEST && grantResults.length > 0 &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            startFlameService();
            updateControls();
        }
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    private final class NightBackgroundView extends View {
        private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);

        NightBackgroundView() {
            super(MainActivity.this);
        }

        @Override
        protected void onDraw(android.graphics.Canvas canvas) {
            super.onDraw(canvas);
            float cx = getWidth() * 0.5f;
            float cy = getHeight() * 0.5f;
            paint.setShader(new RadialGradient(
                    cx, cy, Math.max(getWidth(), getHeight()) * 0.7f,
                    new int[]{Color.rgb(20, 29, 43), Color.rgb(3, 10, 24), Color.BLACK},
                    new float[]{0f, 0.45f, 1f}, Shader.TileMode.CLAMP));
            canvas.drawRect(0, 0, getWidth(), getHeight(), paint);
            paint.setShader(null);
        }
    }
}
