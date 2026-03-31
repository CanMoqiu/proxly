<div align="center">
  <img src="icon.png" width="96" alt="Proxly" />
  <h1>Proxly</h1>
  <p>专为 OpenClash / Mihomo 设计的 Android 原生监控面板</p>
  <p>无需打开浏览器，在手机上实时掌握代理状态、流量用量与连接详情。</p>
</div>

---

## 功能特性

| 功能 | 说明 |
|------|------|
| 实时流量监控 | 上传/下载速度图表与累计流量，每秒刷新 |
| 代理控制台 | 内置 Zashboard，支持代理/规则视图切换，可在线更新面板版本 |
| 出站链路 | 实时连接列表，展示完整代理链、规则、元数据及实时速度 |
| 订阅流量 | 展示各订阅剩余用量与到期时间 |
| 一键重启 | 通过 SSH 远程重启 OpenClash 内核 |
| 内核日志 | WebSocket 实时日志流，支持级别筛选 |
| 设置向导 | 首次启动引导完成连接配置 |
| 深浅色主题 | 跟随系统，Zashboard 主题自动同步 |

---

## 使用说明

### 基础配置

1. 安装并打开 Proxly
2. 首次启动显示设置向导，填写以下信息：
   - **Clash 地址**：路由器 IP + API 端口，例如 `192.168.1.1:9090`
   - **API Secret**：Clash 配置中设置的 `secret`（未设置则留空）
3. 保存后返回首页，流量数据即开始刷新

### 代理控制台

- 底部导航栏点击「代理」进入内置 Zashboard
- 左上角图标可在**代理**视图与**规则**视图之间切换
- 右上角可导入 Zashboard JSON 配置文件，或在线更新面板版本

### 一键重启 Clash

- 首页点击重启按钮，输入路由器 SSH 密码（默认用户 `root`）
- 重启后自动轮询，上线后提示成功

---

## 构建

**环境要求**

- Flutter 3.6+
- Android SDK（minSdk 21）

```bash
flutter pub get
flutter build apk --release
```

产物路径：`build/app/outputs/flutter-apk/app-release.apk`

---

## 依赖

| 库 | 协议 | 用途 |
|----|------|------|
| [Zashboard](https://github.com/Zephyruso/zashboard) | MIT | 内置代理控制面板 |
| [flutter_inappwebview](https://github.com/pichillilorenzo/flutter_inappwebview) | Apache-2.0 | WebView 渲染 |
| [dartssh2](https://github.com/TerminalStudio/dartssh2) | MIT | SSH 重启 |
| [archive](https://pub.dev/packages/archive) | BSD-3-Clause | 解压面板更新包 |
| [path_provider](https://pub.dev/packages/path_provider) | BSD-3-Clause | 本地路径 |
| [shared_preferences](https://pub.dev/packages/shared_preferences) | BSD-3-Clause | 配置持久化 |
| [flutter_svg](https://pub.dev/packages/flutter_svg) | MIT | SVG 图标渲染 |
| [file_picker](https://pub.dev/packages/file_picker) | MIT | 导入配置文件 |

---

## 声明

Proxly 与 Clash / OpenClash / Mihomo 项目无官方关联，仅为个人使用工具。

## License

[MIT](LICENSE) © 2026 Proxly