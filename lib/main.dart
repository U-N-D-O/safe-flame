import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _controlChannel = MethodChannel('com.qila.safeflame/control');

enum FlameMode {
  fireplace('files/SafeFlame/Resources/fireplace.png', Color(0xFFFF9426)),
  candle('files/SafeFlame/Resources/candle.png', Color(0xFFFF7A29)),
  moonlight('files/SafeFlame/Resources/moon.png', Color(0xFF6B9EFF));

  const FlameMode(this.asset, this.accent);
  final String asset;
  final Color accent;
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SafeFlameApp());
}

class SafeFlameApp extends StatelessWidget {
  const SafeFlameApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Safe Flame',
        home: SafeFlameHome(),
      );
}

class SafeFlameHome extends StatefulWidget {
  const SafeFlameHome({super.key});

  @override
  State<SafeFlameHome> createState() => _SafeFlameHomeState();
}

class _SafeFlameHomeState extends State<SafeFlameHome> {
  FlameMode _mode = FlameMode.fireplace;
  bool _running = false;
  bool _dimmed = false;

  @override
  void initState() {
    super.initState();
    _loadServiceState();
  }

  Future<void> _loadServiceState() async {
    bool running = false;
    try {
      running = await _controlChannel.invokeMethod<bool>('isRunning') ?? false;
    } on PlatformException {
      running = false;
    } on MissingPluginException {
      running = false;
    }
    if (mounted) setState(() => _running = running);
  }

  Future<void> _toggle() async {
    if (_running) {
      await _controlChannel.invokeMethod<void>('stop');
      if (mounted) setState(() => _running = false);
      return;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      final prefs = await SharedPreferences.getInstance();
      final hasReadNotice = prefs.getBool('android_camera_notice_seen') ?? false;
      if (!hasReadNotice) {
        final accepted = await _showAndroidCameraNotice();
        if (!accepted) return;
        await prefs.setBool('android_camera_notice_seen', true);
      }
    }

    final started = await _controlChannel.invokeMethod<bool>('start', {'mode': _mode.index}) ?? false;
    if (mounted && started) setState(() => _running = true);
  }

  Future<bool> _showAndroidCameraNotice() async {
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 26, vertical: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 430),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            image: const DecorationImage(
              image: AssetImage('files/SafeFlame/Resources/like.jpg'),
              fit: BoxFit.cover,
              colorFilter: ColorFilter.mode(Color(0xB9081024), BlendMode.darken),
            ),
            border: Border.all(color: const Color(0xFF7386A5).withValues(alpha: 0.28)),
            boxShadow: [
              const BoxShadow(color: Colors.black87, blurRadius: 24, offset: Offset(12, 14)),
              BoxShadow(color: const Color(0xFFB9C9E2).withValues(alpha: 0.12), blurRadius: 16, offset: const Offset(-8, -8)),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(27),
            child: Container(
              padding: const EdgeInsets.fromLTRB(25, 25, 25, 18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF07142C).withValues(alpha: 0.92),
                    const Color(0xFF1A1930).withValues(alpha: 0.86),
                    const Color(0xFF3A2426).withValues(alpha: 0.72),
                  ],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Welcome to Safe Flame',
                    style: TextStyle(color: Color(0xFFFFD27A), fontSize: 21, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 16),
                  RichText(
                    text: const TextSpan(
                      style: TextStyle(color: Color(0xFFE4EBF7), fontSize: 16, height: 1.42),
                      children: [
                        TextSpan(text: 'Safe Flame uses your phone’s flashlight to create a soft, calming glow. It needs permission to access the camera system, but only the flashlight is used.\n\n'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Align(
                    alignment: Alignment.centerRight,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: const LinearGradient(colors: [Color(0xFF314663), Color(0xFF142238)]),
                        border: Border.fromBorderSide(BorderSide(color: Color(0xFF9FB4D0), width: 0.7)),
                        boxShadow: const [
                          BoxShadow(color: Colors.black54, blurRadius: 8, offset: Offset(4, 5)),
                          BoxShadow(color: Color(0x337F96B7), blurRadius: 7, offset: Offset(-3, -3)),
                        ],
                      ),
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFFFD27A),
                          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('OK', style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return accepted ?? false;
  }

  Future<void> _changeMode(int direction) async {
    final next = (_mode.index + direction + FlameMode.values.length) % FlameMode.values.length;
    final selected = FlameMode.values[next];
    if (mounted) setState(() => _mode = selected);
    if (_running) {
      await _controlChannel.invokeMethod<void>('stop');
      final started = await _controlChannel.invokeMethod<bool>('start', {'mode': selected.index}) ?? false;
      if (mounted && !started) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _mode.accent;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  radius: 1.05,
                  colors: [
                    const Color(0xFF1F293A).withValues(alpha: _running ? 0.22 : 0.12),
                    Colors.black,
                  ],
                ),
              ),
            ),
            Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _arrow(Icons.chevron_left, -1),
                    const SizedBox(width: 22),
                    GestureDetector(
                      onTap: _toggle,
                      child: Container(
                        width: 116,
                        height: 116,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [Color(0xFF28364B), Color(0xFF0B1320)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.10), width: 1),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: 0.82), blurRadius: 16, offset: const Offset(9, 10)),
                            BoxShadow(color: Colors.white.withValues(alpha: 0.07), blurRadius: 11, offset: const Offset(-7, -7)),
                            BoxShadow(color: accent.withValues(alpha: _running ? 0.22 : 0.06), blurRadius: _running ? 24 : 12),
                          ],
                        ),
                        child: Container(
                          margin: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _running ? accent.withValues(alpha: 0.42) : Colors.white.withValues(alpha: 0.05),
                              width: 1.5,
                            ),
                          ),
                          child: Center(child: Image.asset(_mode.asset, width: 66, height: 66, fit: BoxFit.contain)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 22),
                    _arrow(Icons.chevron_right, 1),
                  ],
                ),
                ),
                if (_running && !_dimmed)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 18,
                    child: Center(
                      child: GestureDetector(
                        onTap: () => setState(() => _dimmed = true),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF0B1320),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                            boxShadow: const [
                              BoxShadow(color: Colors.black54, blurRadius: 8, offset: Offset(5, 6)),
                              BoxShadow(color: Color(0x337F96B7), blurRadius: 7, offset: Offset(-4, -4)),
                            ],
                          ),
                          child: Icon(Icons.lock, size: 17, color: Colors.white.withValues(alpha: 0.42)),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (_dimmed)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _dimmed = false),
                onPanDown: (_) => setState(() => _dimmed = false),
                child: const ColoredBox(color: Colors.black),
              ),
          ],
        ),
      ),
    );
  }

  Widget _arrow(IconData icon, int direction) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _changeMode(direction),
        child: SizedBox(
          width: 36,
          height: 64,
          child: Icon(icon, size: 22, color: Colors.white.withValues(alpha: 0.48)),
        ),
      );
}
