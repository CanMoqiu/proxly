import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/clash_service.dart';
import 'pages/main_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ClashService.instance.loadConfig();
  runApp(const ProxlyApp());
}

class ProxlyApp extends StatefulWidget {
  const ProxlyApp({super.key});

  static void toggleThemeOf(BuildContext context) {
    context.findAncestorStateOfType<_ProxlyAppState>()?.toggleTheme();
  }

  static void setBallVisibilityOf(BuildContext context, bool value) {
    context.findAncestorStateOfType<_ProxlyAppState>()?.setBallVisibility(value);
  }

  @override
  State<ProxlyApp> createState() => _ProxlyAppState();
}

class _ProxlyAppState extends State<ProxlyApp> {
  ThemeMode _themeMode = ThemeMode.system;
  bool _showBall = false;

  @override
  void initState() {
    super.initState();
    _loadBallPref();
  }

  Future<void> _loadBallPref() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _showBall = prefs.getBool('show_floating_ball') ?? false);
  }

  void toggleTheme() {
    final currentIsDark = _themeMode == ThemeMode.dark ||
        (_themeMode == ThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark);
    setState(() {
      _themeMode = currentIsDark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  void setBallVisibility(bool value) => setState(() => _showBall = value);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Proxly',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFFAFAFA),
        colorScheme: const ColorScheme.light(
            primary: Color(0xFF378ADD), surface: Colors.white),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF1D232A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF378ADD),
          surface: Color(0xFF191E24),
        ),
        useMaterial3: true,
      ),
      builder: (context, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness:
                isDark ? Brightness.light : Brightness.dark,
          ),
          child: Stack(
            children: [
              child!,
              if (_showBall) const _FloatingThemeBall(),
            ],
          ),
        );
      },
      home: const MainShell(),
    );
  }
}

// ─── 悬浮主题切换球 ────────────────────────────────────────────────────────────

class _FloatingThemeBall extends StatefulWidget {
  const _FloatingThemeBall();

  @override
  State<_FloatingThemeBall> createState() => _FloatingThemeBallState();
}

class _FloatingThemeBallState extends State<_FloatingThemeBall> {
  Offset? _pos;
  bool _isDragging = false;
  Offset _posAtDragStart = Offset.zero;
  Offset _dragOrigin = Offset.zero;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_pos == null) {
      final size = MediaQuery.sizeOf(context);
      _pos = Offset(size.width - 64, size.height * 0.38);
    }
  }

  void _snapToEdge(Size size) {
    final p = _pos!;
    setState(() {
      _pos = Offset(
        p.dx + 24 < size.width / 2 ? 8.0 : size.width - 56.0,
        p.dy.clamp(8.0, size.height - 56.0),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pos = _pos ?? Offset(size.width - 64, size.height * 0.38);

    return AnimatedPositioned(
      duration: _isDragging ? Duration.zero : const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      left: pos.dx,
      top: pos.dy,
      child: GestureDetector(
        onTap: () => ProxlyApp.toggleThemeOf(context),
        onLongPressStart: (d) {
          setState(() {
            _isDragging = true;
            _posAtDragStart = _pos!;
            _dragOrigin = d.globalPosition;
          });
        },
        onLongPressMoveUpdate: (d) {
          final delta = d.globalPosition - _dragOrigin;
          setState(() {
            _pos = Offset(
              (_posAtDragStart.dx + delta.dx).clamp(0, size.width - 48),
              (_posAtDragStart.dy + delta.dy).clamp(0, size.height - 48),
            );
          });
        },
        onLongPressEnd: (_) {
          _snapToEdge(size);
          setState(() => _isDragging = false);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF378ADD)
                .withValues(alpha: _isDragging ? 1.0 : 0.82),
            boxShadow: [
              BoxShadow(
                color: Colors.black
                    .withValues(alpha: _isDragging ? 0.28 : 0.14),
                blurRadius: _isDragging ? 16 : 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Icon(
            isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
            color: Colors.white,
            size: 22,
          ),
        ),
      ),
    );
  }
}
