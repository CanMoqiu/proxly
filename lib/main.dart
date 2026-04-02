import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/clash_service.dart';
import 'pages/main_shell.dart' show MainShell, shellRouteObserver;
import 'pages/setup_wizard_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ClashService.instance.loadConfig();
  // 检测是否首次启动（clash_host 为空则显示设置向导）
  final prefs = await SharedPreferences.getInstance();
  final isFirstLaunch = (prefs.getString('clash_host') ?? '').isEmpty;
  runApp(ProxlyApp(showSetupWizard: isFirstLaunch));
}

class ProxlyApp extends StatefulWidget {
  final bool showSetupWizard;
  const ProxlyApp({super.key, this.showSetupWizard = false});

  // 静态变量，供子页面同步读取，无需本地副本
  static ThemeMode activeThemeMode = ThemeMode.system;

  static void toggleThemeOf(BuildContext context) {
    context.findAncestorStateOfType<_ProxlyAppState>()?.toggleTheme();
  }

  static void setBallVisibilityOf(BuildContext context, bool value) {
    context.findAncestorStateOfType<_ProxlyAppState>()?.setBallVisibility(value);
  }

  static void setThemeModeOf(BuildContext context, ThemeMode mode) {
    context.findAncestorStateOfType<_ProxlyAppState>()?.setThemeMode(mode);
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
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final modeStr = prefs.getString('theme_mode') ?? 'system';
    final mode = modeStr == 'light'
        ? ThemeMode.light
        : modeStr == 'dark'
            ? ThemeMode.dark
            : ThemeMode.system;
    ProxlyApp.activeThemeMode = mode;
    setState(() {
      _showBall = prefs.getBool('show_floating_ball') ?? false;
      _themeMode = mode;
    });
  }

  void toggleTheme() {
    final currentIsDark = _themeMode == ThemeMode.dark ||
        (_themeMode == ThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark);
    final next = currentIsDark ? ThemeMode.light : ThemeMode.dark;
    ProxlyApp.activeThemeMode = next;
    setState(() => _themeMode = next);
  }

  void setThemeMode(ThemeMode mode) {
    ProxlyApp.activeThemeMode = mode;
    setState(() => _themeMode = mode);
  }

  void setBallVisibility(bool value) => setState(() => _showBall = value);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Proxly',
      debugShowCheckedModeBanner: false,
      navigatorObservers: [shellRouteObserver],
      themeMode: _themeMode,
      themeAnimationDuration: Duration.zero,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF5F5F5),
        colorScheme: const ColorScheme.light(
            primary: Color(0xFF1A73E8), surface: Colors.white),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF4DA3F5),
          surface: Color(0xFF1E1E1E),
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
      // 首次启动（未配置地址）显示设置向导，否则直接进入主界面
      home: widget.showSetupWizard ? const SetupWizardPage() : const MainShell(),
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
            color: const Color(0xFF1A73E8)
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
