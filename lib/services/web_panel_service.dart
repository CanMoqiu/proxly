import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:archive/archive.dart';

class WebPanelVersionInfo {
  final String tag;
  final String downloadUrl;
  const WebPanelVersionInfo({required this.tag, required this.downloadUrl});
}

class WebPanelService {
  static const _prefVersion = 'webpanel_version';
  static const _prefPath = 'webpanel_path';

  static Future<String?> getInstalledVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefVersion);
  }

  static Future<String?> getInstalledPath() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(_prefPath);
    if (path != null && Directory(path).existsSync()) return path;
    return null;
  }

  static Future<WebPanelVersionInfo> checkLatest() async {
    final response = await http
        .get(
          Uri.parse(
              'https://api.github.com/repos/Zephyruso/zashboard/releases/latest'),
          headers: {'Accept': 'application/vnd.github.v3+json'},
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('GitHub API 请求失败 (${response.statusCode})');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final tag = data['tag_name'] as String;
    final assets = data['assets'] as List;

    final distAsset = assets.firstWhere(
      (a) => (a['name'] as String).toLowerCase() == 'dist.zip',
      orElse: () => throw Exception('发布包中未找到 dist.zip'),
    );

    return WebPanelVersionInfo(
      tag: tag,
      downloadUrl: distAsset['browser_download_url'] as String,
    );
  }

  static Future<void> downloadAndInstall(
    WebPanelVersionInfo info,
    void Function(double progress) onProgress,
  ) async {
    final appDir = await getApplicationSupportDirectory();
    final baseDir = Directory('${appDir.path}/zashboard');
    await baseDir.create(recursive: true);

    final zipFile = File('${baseDir.path}/download.zip');
    final newDir = Directory('${baseDir.path}/${info.tag}');

    try {
      // 第一步：下载压缩包
      final request = http.Request('GET', Uri.parse(info.downloadUrl));
      final response = await request.send();
      final total = response.contentLength ?? 0;
      int received = 0;

      final sink = zipFile.openWrite();
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) onProgress(received / total * 0.75);
        }
      } finally {
        await sink.flush();
        await sink.close();
      }
      onProgress(0.80);

      // 第二步：解压到版本目录
      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      onProgress(0.85);

      // 检测压缩包是否有公共前缀目录（兼容 dist/ 和无前缀两种打包结构）
      String? prefix;
      for (final file in archive) {
        if (file.name.isEmpty) continue;
        final slash = file.name.indexOf('/');
        if (slash > 0) {
          final p = file.name.substring(0, slash + 1);
          if (prefix == null) {
            prefix = p;
          } else if (prefix != p) {
            prefix = null;
            break;
          }
        } else {
          prefix = null;
          break;
        }
      }

      await newDir.create(recursive: true);
      for (final file in archive) {
        String name = file.name;
        if (prefix != null && name.startsWith(prefix)) {
          name = name.substring(prefix.length);
        }
        if (name.isEmpty) continue;

        final outPath = '${newDir.path}/$name';
        if (file.isFile) {
          final outFile = File(outPath);
          await outFile.create(recursive: true);
          await outFile.writeAsBytes(file.content as List<int>);
        } else {
          await Directory(outPath).create(recursive: true);
        }
      }

      // 验证 index.html 存在，确保解压结果有效
      if (!File('${newDir.path}/index.html').existsSync()) {
        await newDir.delete(recursive: true);
        throw Exception('解压后未找到 index.html，发布包格式有误');
      }
      onProgress(0.95);

      // 第三步：删除旧版本目录
      final prefs = await SharedPreferences.getInstance();
      final oldPath = prefs.getString(_prefPath);
      if (oldPath != null && oldPath != newDir.path) {
        final oldDir = Directory(oldPath);
        if (oldDir.existsSync()) await oldDir.delete(recursive: true);
      }

      // 第四步：持久化版本号和安装路径
      await prefs.setString(_prefVersion, info.tag);
      await prefs.setString(_prefPath, newDir.path);

      onProgress(1.0);
    } catch (e) {
      // 下载或解压失败时清理残留文件
      if (zipFile.existsSync()) await zipFile.delete();
      if (newDir.existsSync()) await newDir.delete(recursive: true);
      rethrow;
    } finally {
      if (zipFile.existsSync()) await zipFile.delete();
    }
  }
}

/// 本地 HTTP 文件服务器，供 InAppWebView 加载已下载的面板版本
class FileHttpServer {
  HttpServer? _server;
  final String rootPath;
  int _port = 0;

  FileHttpServer(this.rootPath);

  int get port => _port;

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _port = _server!.port;
    _server!.listen(_handle);
  }

  Future<void> close() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handle(HttpRequest request) async {
    var path = request.uri.path;
    if (path == '/' || path.isEmpty) path = '/index.html';

    // 拦截路径穿越攻击
    if (path.contains('..')) {
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
      return;
    }

    final file = File('$rootPath$path');
    if (file.existsSync()) {
      request.response.headers
          .set(HttpHeaders.contentTypeHeader, _contentType(path));
      request.response.headers.set('Access-Control-Allow-Origin', '*');
      await request.response.addStream(file.openRead());
    } else {
      // SPA 路由兜底：未知路径统一返回 index.html
      final index = File('$rootPath/index.html');
      if (index.existsSync()) {
        request.response.headers
            .set(HttpHeaders.contentTypeHeader, 'text/html; charset=utf-8');
        await request.response.addStream(index.openRead());
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
    }
    await request.response.close();
  }

  String _contentType(String path) {
    if (path.endsWith('.html')) return 'text/html; charset=utf-8';
    if (path.endsWith('.js') || path.endsWith('.mjs')) {
      return 'application/javascript';
    }
    if (path.endsWith('.css')) return 'text/css';
    if (path.endsWith('.json')) return 'application/json';
    if (path.endsWith('.png')) return 'image/png';
    if (path.endsWith('.svg')) return 'image/svg+xml';
    if (path.endsWith('.ico')) return 'image/x-icon';
    if (path.endsWith('.woff2')) return 'font/woff2';
    if (path.endsWith('.woff')) return 'font/woff';
    if (path.endsWith('.webmanifest')) return 'application/manifest+json';
    return 'application/octet-stream';
  }
}
