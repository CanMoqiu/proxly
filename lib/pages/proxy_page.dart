import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
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

  // 代理页内视图切换：proxies ↔ rules
  bool _showingRules = false;

  bool _updating = false;
  double _updateProgress = 0;
  String _updateMessage = '';
  bool _updateFailed = false;

  static const _prefLocalStorage = 'webpanel_localstorage';

  // 在 Vue 初始化前注入 localStorage 的 UserScript
  UserScript? _restoreUserScript;

  @override
  void initState() {
    super.initState();
    if (widget.asTab) {
      WebPanelSync.instance.register(
        save: _saveLocalStorage,
        reload: _reloadFromPrefs,
      );
    }
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

  /// 在 AT_DOCUMENT_START 屏蔽 navigator.serviceWorker，
  /// 防止 Service Worker 在隐藏的 WebView（Virtual Display 0×0）中安装时挂起页面加载。
  static final UserScript _noSwScript = UserScript(
    source: "Object.defineProperty(navigator,'serviceWorker',{get:()=>undefined});",
    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
  );

  /// 移除所有 UserScript 后重新注入：SW 屏蔽脚本 + localStorage 恢复脚本。
  Future<void> _reapplyUserScripts() async {
    if (_webViewController == null) return;
    await _webViewController!.removeAllUserScripts();
    await _webViewController!.addUserScript(userScript: _noSwScript);
    if (_restoreUserScript != null) {
      await _webViewController!.addUserScript(userScript: _restoreUserScript!);
    }
  }

  /// 从 SharedPreferences 读取已保存的 localStorage，
  /// 构建一个在 Vue 初始化之前（AT_DOCUMENT_START）注入数据的 UserScript。
  /// 使用 base64 编码规避 JSON 中特殊字符对 JS 字符串的干扰。
  Future<void> _buildRestoreScript() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefLocalStorage);
    if (raw == null || raw.isEmpty) {
      _restoreUserScript = null;
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) { _restoreUserScript = null; return; }
    } catch (_) {
      _restoreUserScript = null;
      return;
    }
    final b64 = base64Encode(utf8.encode(raw));
    _restoreUserScript = UserScript(
      source: """
(function(){try{
  const d=JSON.parse(atob('$b64'));
  for(const [k,v] of Object.entries(d)){localStorage.setItem(k,v);}
}catch(e){}})();
""",
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    );
  }

  Future<void> _startLocalServer() async {
    // 先构建恢复脚本，确保 WebView 创建时可立即注入
    await _buildRestoreScript();

    try {
      final downloadedPath = await WebPanelService.getInstalledPath();
      if (downloadedPath != null) {
        _fileServer = FileHttpServer(downloadedPath);
        await _fileServer!.start();
        _serverPort = _fileServer!.port;
      } else {
        // 控制台复用代理页已启动的 InAppLocalhostServer，避免同端口重复绑定
        final shared = WebPanelSync.instance.sharedAssetServerPort;
        if (!widget.asTab && shared != 0) {
          _serverPort = shared;
        } else {
          _assetServer = InAppLocalhostServer(documentRoot: 'assets/web_panel');
          await _assetServer!.start();
          _serverPort = _assetServer!.port;
          if (widget.asTab) WebPanelSync.instance.sharedAssetServerPort = _serverPort;
        }
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
    if (widget.asTab) WebPanelSync.instance.unregister();
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

  /// 控制台关闭后，把最新的 SharedPreferences 数据注入到代理页已有的 WebView，
  /// 无需整页重载，用户不会看到加载动画。
  Future<void> _reloadFromPrefs() async {
    if (_webViewController == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefLocalStorage);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final b64 = base64Encode(utf8.encode(raw));
      await _webViewController!.evaluateJavascript(source: """
(function(){try{
  const d=JSON.parse(atob('$b64'));
  for(const [k,v] of Object.entries(d)){localStorage.setItem(k,v);}
}catch(e){}})();
""");
      // 同步更新 UserScript，下次重载时依然生效
      await _buildRestoreScript();
      await _reapplyUserScripts();
    } catch (e) {
      debugPrint('[ProxyPage] _reloadFromPrefs 失败: $e');
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

  /// 在代理页内切换 proxies / rules 视图（SPA 哈希路由，不触发页面重载）
  void _toggleView() {
    setState(() => _showingRules = !_showingRules);
    final hash = _showingRules ? '#/rules' : '#/proxies';
    _webViewController?.evaluateJavascript(
        source: "window.location.hash = '$hash';");
    // SPA 路由跳转不触发 onLoadStop，主动补注隐藏 Dock 样式
    _hideDock();
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

  /// 从本地 JSON 文件导入 Zashboard 配置。
  /// 通过更新 AT_DOCUMENT_START UserScript，确保重载后 Vue 初始化时
  /// 能读取到正确的 localStorage，而非写入已初始化的 Vue 状态。
  Future<void> _importZashboardConfig() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final bytes = result.files.first.bytes;
    if (bytes == null) {
      _showImportSnack('读取文件失败', success: false);
      return;
    }

    Map<String, dynamic> data;
    String raw;
    try {
      raw = const Utf8Codec().decode(bytes);
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        _showImportSnack('格式错误：不是有效的配置文件', success: false);
        return;
      }
      data = Map<String, dynamic>.from(decoded);
    } catch (_) {
      _showImportSnack('解析失败：文件内容不是合法 JSON', success: false);
      return;
    }

    if (_webViewController == null) {
      _showImportSnack('面板尚未加载，请稍后再试', success: false);
      return;
    }

    // 1. 持久化到 SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefLocalStorage, raw);

    // 2. 重建 UserScript，让下次页面加载时在 Vue 初始化前注入数据
    await _buildRestoreScript();
    await _reapplyUserScripts();

    if (!mounted) return;
    _showImportSnack('已导入 ${data.length} 项配置，正在重载…', success: true);

    // 3. 重载页面，UserScript 将在 Vue 初始化前把数据写入 localStorage
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    setState(() => _webViewReady = false);
    await _webViewController!.reload();
  }

  void _showImportSnack(String msg, {required bool success}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor:
          success ? const Color(0xFF1D9E75) : const Color(0xFFE24B4A),
      duration: const Duration(seconds: 3),
    ));
  }

  Future<void> _performNativeUpdate() async {
    if (_updating) return;
    // 先持久化当前配置，防止更新后 origin 变化导致 localStorage 丢失
    await _saveLocalStorage();
    // 重建注入脚本，确保新服务器端口下页面加载时仍能恢复配置
    await _buildRestoreScript();
    await _reapplyUserScripts();
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

    final scaffold = Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        leading: widget.asTab
            ? IconButton(
                tooltip: _showingRules ? '代理' : '规则',
                onPressed: _toggleView,
                icon: SvgPicture.asset(
                  _showingRules
                      ? 'assets/icons/globe-alt.svg'
                      : 'assets/icons/swatch.svg',
                  width: 22,
                  height: 22,
                  colorFilter: ColorFilter.mode(textColor, BlendMode.srcIn),
                ),
              )
            : IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: textColor),
                onPressed: () async {
                  await _saveLocalStorage();
                  if (mounted) Navigator.of(context).pop();
                },
              ),
        title: Text(
          widget.asTab ? (_showingRules ? '规则' : '代理') : '控制台',
          style: TextStyle(
              color: textColor, fontSize: 16, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        actions: [
          // 导入 Zashboard 配置文件
          IconButton(
            icon: Icon(Icons.file_upload_outlined, color: textColor, size: 22),
            tooltip: '导入配置',
            onPressed: _importZashboardConfig,
          ),
        ],
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
                // 切换为 Virtual Display 渲染，减少 GPU 合成层，解决掉帧问题
                useHybridComposition: false,
                // 确保硬件加速渲染
                hardwareAcceleration: true,
                // 关闭不需要的功能，降低后台开销
                supportZoom: false,
                geolocationEnabled: false,
                safeBrowsingEnabled: false,
              ),
              onWebViewCreated: (c) async {
                _webViewController = c;
                // 注入 SW 屏蔽脚本 + localStorage 恢复脚本（AT_DOCUMENT_START）
                await c.addUserScript(userScript: _noSwScript);
                if (_restoreUserScript != null) {
                  await c.addUserScript(userScript: _restoreUserScript!);
                }
                c.addJavaScriptHandler(
                  handlerName: 'nativeUpdatePanel',
                  callback: (_) => _performNativeUpdate(),
                );
              },
              onLoadStop: (_, __) async {
                _syncTheme(_isDark);
                _injectInterceptor();
                // 底栏代理页隐藏 Zashboard 自带 Dock；控制台保留
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

    // 控制台（asTab:false）用 PopScope 拦截系统返回，确保 localStorage
    // 保存完成后再 pop，避免 HomePage 调用 reload() 时读到旧数据
    if (!widget.asTab) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (bool didPop, Object? result) {
          if (didPop) return;
          _saveLocalStorage().then((_) {
            if (mounted) Navigator.of(context).pop();
          });
        },
        child: scaffold,
      );
    }
    return scaffold;
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
