import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../services/web_panel_service.dart';

class ProxyPage extends StatefulWidget {
  final bool asTab;
  const ProxyPage({super.key, this.asTab = false});

  @override
  State<ProxyPage> createState() => _ProxyPageState();
}

class _ProxyPageState extends State<ProxyPage> {
  InAppLocalhostServer? _assetServer;
  FileHttpServer? _fileServer;
  int _serverPort = 0;
  bool _serverStarted = false;
  String _targetUrl = '';
  String _clashQuery = '';
  InAppWebViewController? _webViewController;
  bool _isDark = false;
  bool _webViewReady = false;

  bool _updating = false;
  double _updateProgress = 0;
  String _updateMessage = '';
  bool _updateFailed = false;

  static const _prefLocalStorage = 'webpanel_localstorage';

  @override
  void initState() {
    super.initState();
    _startLocalServer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final currentIsDark = Theme.of(context).brightness == Brightness.dark;
    if (_isDark != currentIsDark) {
      _isDark = currentIsDark;
      _syncTheme(_isDark);
    }
  }

  Future<void> _startLocalServer() async {
    try {
      final downloadedPath = await WebPanelService.getInstalledPath();
      if (downloadedPath != null) {
        _fileServer = FileHttpServer(downloadedPath);
        await _fileServer!.start();
        _serverPort = _fileServer!.port;
      } else {
        _assetServer = InAppLocalhostServer(documentRoot: 'assets/web_panel');
        await _assetServer!.start();
        _serverPort = _assetServer!.port;
      }
    } catch (e) {
      debugPrint('[ProxyPage] 本地服务器启动失败: $e');
    }

    final prefs = await SharedPreferences.getInstance();
    final host = prefs.getString('clash_host') ?? '127.0.0.1:9090';
    final token = prefs.getString('clash_token') ?? '';

    String hostname = host;
    String port = '9090';
    if (host.contains(':')) {
      final parts = host.split(':');
      hostname = parts[0];
      port = parts[1];
    }

    _clashQuery = 'hostname=$hostname&port=$port';
    if (token.isNotEmpty) _clashQuery += '&secret=$token';

    if (mounted) {
      setState(() {
        _targetUrl = 'http://127.0.0.1:$_serverPort/?$_clashQuery#/proxies';
        _serverStarted = true;
      });
    }
  }

  @override
  void dispose() {
    _saveLocalStorage(); // 关闭页面时保存
    _assetServer?.close();
    _fileServer?.close();
    super.dispose();
  }

  /// 把当前 WebView 的 localStorage 全部导出并存入 SharedPreferences
  Future<void> _saveLocalStorage() async {
    if (_webViewController == null) return;
    try {
      final result = await _webViewController!.evaluateJavascript(source: r"""
        (function() {
          const obj = {};
          for (let i = 0; i < localStorage.length; i++) {
            const k = localStorage.key(i);
            obj[k] = localStorage.getItem(k);
          }
          return JSON.stringify(obj);
        })()
      """);
      if (result == null) return;
      // JS 返回值已是 Dart 原生字符串类型，直接转换
      final raw = result is String ? result : result.toString();
      if (raw.isEmpty || raw == 'null') return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefLocalStorage, raw);
    } catch (e) {
      debugPrint('[ProxyPage] 保存 localStorage 失败: $e');
    }
  }

  /// 把保存的 localStorage 注入回 WebView
  Future<void> _restoreLocalStorage() async {
    if (_webViewController == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefLocalStorage);
      if (raw == null || raw.isEmpty) return;
      // 验证 JSON 合法性，序列化为安全的 JS 字面量
      final map = jsonDecode(raw);
      if (map is! Map) return;
      final escaped = raw
          .replaceAll(r'\', r'\\')
          .replaceAll("'", r"\'");
      await _webViewController!.evaluateJavascript(source: """
        (function() {
          try {
            const data = JSON.parse('$escaped');
            for (const [k, v] of Object.entries(data)) {
              localStorage.setItem(k, v);
            }
          } catch(e) {}
        })();
      """);
    } catch (e) {
      debugPrint('[ProxyPage] 恢复 localStorage 失败: $e');
    }
  }

  void _syncTheme(bool isDark) {
    if (_webViewController == null) return;
    final t = isDark ? 'dark' : 'light';
    _webViewController!.evaluateJavascript(source: """
      localStorage.setItem('theme', '$t');
      document.documentElement.setAttribute('data-theme', '$t');
      document.documentElement.classList.toggle('dark', $isDark);
    """);
  }

  void _hideDock() {
    _webViewController?.evaluateJavascript(source: r"""
      (function() {
        const style = document.getElementById('__proxly_no_dock');
        if (style) return;
        const s = document.createElement('style');
        s.id = '__proxly_no_dock';
        s.textContent = '.dock { display: none !important; }';
        document.head.appendChild(s);
      })();
    """);
  }

  /// 注入 JS，拦截 POST /upgrade/ui 并转给 Flutter 处理
  void _injectInterceptor() {
    _webViewController?.evaluateJavascript(source: r"""
      (function() {
        if (window.__proxlyIntercepted) return;
        window.__proxlyIntercepted = true;
        const _orig = window.fetch;
        window.fetch = function(input, init) {
          const url = (typeof input === 'string' ? input : (input && input.url)) || '';
          const method = ((init && init.method) || 'GET').toUpperCase();
          if (method === 'POST' && url.includes('/upgrade/ui')) {
            window.flutter_inappwebview.callHandler('nativeUpdatePanel');
            return Promise.resolve(
              new Response('{}', { status: 200,
                headers: { 'Content-Type': 'application/json' } })
            );
          }
          return _orig.apply(this, arguments);
        };
      })();
    """);
  }

  Future<void> _performNativeUpdate() async {
    if (_updating) return;
    // 先持久化当前配置，防止更新后 origin 变化导致 localStorage 丢失
    await _saveLocalStorage();
    setState(() {
      _updating = true;
      _updateProgress = 0;
      _updateMessage = '正在检查最新版本…';
      _updateFailed = false;
    });

    try {
      final info = await WebPanelService.checkLatest();
      if (!mounted) return;
      setState(() => _updateMessage = '下载 ${info.tag}…');

      await WebPanelService.downloadAndInstall(info, (p) {
        if (mounted) {
          setState(() {
            _updateProgress = p;
            _updateMessage = p < 0.8
                ? '下载 ${info.tag}… ${(p * 100).toInt()}%'
                : '正在解压…';
          });
        }
      });

      if (!mounted) return;

      // 关闭旧服务器，重新指向新版本目录
      final newPath = await WebPanelService.getInstalledPath();
      if (newPath != null) {
        await _fileServer?.close();
        _assetServer?.close();
        _assetServer = null;
        _fileServer = FileHttpServer(newPath);
        await _fileServer!.start();
        _serverPort = _fileServer!.port;
      }

      if (!mounted) return;
      setState(() {
        _updateMessage = '更新完成，正在重载…';
        _updateProgress = 1.0;
      });

      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;

      final newUrl = 'http://127.0.0.1:$_serverPort/?$_clashQuery#/proxies';
      setState(() {
        _targetUrl = newUrl;
        _updating = false;
        _webViewReady = false;
      });
      await _webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(newUrl)));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _updating = false;
        _updateFailed = true;
        _updateMessage = '更新失败：$e';
      });
      // 4 秒后自动清除错误提示
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) setState(() => _updateFailed = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = _isDark ? const Color(0xFF1D232A) : const Color(0xFFFAFAFA);
    final textColor = _isDark ? const Color(0xFFA6ADBB) : Colors.black87;
    final dividerColor = _isDark ? const Color(0xFF2A3140) : const Color(0xFFE2E8F0);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        leading: widget.asTab
            ? null
            : IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: textColor),
                onPressed: () => Navigator.of(context).pop(),
              ),
        title: Text(
          widget.asTab ? '代理' : '控制台',
          style: TextStyle(
              color: textColor, fontSize: 16, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: dividerColor),
        ),
      ),
      body: Stack(
        children: [
          if (_serverStarted)
            InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(_targetUrl)),
              initialSettings: InAppWebViewSettings(
                transparentBackground: false,
                javaScriptEnabled: true,
                domStorageEnabled: true,
                disableHorizontalScroll: true,
                mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
              ),
              onWebViewCreated: (c) {
                _webViewController = c;
                c.addJavaScriptHandler(
                  handlerName: 'nativeUpdatePanel',
                  callback: (_) => _performNativeUpdate(),
                );
              },
              onLoadStop: (_, __) async {
                await _restoreLocalStorage();
                _syncTheme(_isDark);
                _injectInterceptor();
                if (widget.asTab) _hideDock();
                if (mounted) setState(() => _webViewReady = true);
              },
            ),

          // 初始加载动画遮罩层
          AnimatedOpacity(
            opacity: _webViewReady ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOut,
            child: IgnorePointer(
              ignoring: _webViewReady,
              child: _LoadingOverlay(isDark: _isDark, bgColor: bgColor),
            ),
          ),

          // 下载更新进度条
          if (_updating)
            Positioned(
              bottom: 24,
              left: 20,
              right: 20,
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(14),
                color: _isDark ? const Color(0xFF191E24) : Colors.white,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _updateMessage,
                        style: TextStyle(
                          fontSize: 13,
                          color: _isDark
                              ? const Color(0xFFA6ADBB)
                              : const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: _updateProgress,
                          backgroundColor: _isDark
                              ? const Color(0xFF15191E)
                              : const Color(0xFFE2E8F0),
                          valueColor: const AlwaysStoppedAnimation(
                              Color(0xFF378ADD)),
                          minHeight: 5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // 更新失败提示条
          if (_updateFailed)
            Positioned(
              bottom: 24,
              left: 20,
              right: 20,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(12),
                color: const Color(0xFFE24B4A),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Text(
                    _updateMessage,
                    style: const TextStyle(fontSize: 13, color: Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── 加载动画遮罩 ──────────────────────────────────────────────────────────────

class _LoadingOverlay extends StatefulWidget {
  final bool isDark;
  final Color bgColor;

  const _LoadingOverlay({required this.isDark, required this.bgColor});

  @override
  State<_LoadingOverlay> createState() => _LoadingOverlayState();
}

class _LoadingOverlayState extends State<_LoadingOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hintColor =
        widget.isDark ? const Color(0xFF747E8B) : const Color(0xFF94A3B8);

    return Container(
      color: widget.bgColor,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RotationTransition(
              turns: _spin,
              child: SizedBox(
                width: 40,
                height: 40,
                child: CustomPaint(
                  painter: _ArcPainter(color: const Color(0xFF378ADD)),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              '正在加载控制台',
              style: TextStyle(fontSize: 13, color: hintColor, letterSpacing: 0.3),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  final Color color;
  const _ArcPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawArc(
      Rect.fromLTWH(0, 0, size.width, size.height),
      -1.5707963,
      4.712389,
      false,
      Paint()
        ..color = color
        ..strokeWidth = 3.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_ArcPainter old) => old.color != color;
}
