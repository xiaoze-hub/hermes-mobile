# Hermes Agent Mobile (Flutter 跨平台客户端)

专为连接远程 Linux 服务器常驻部署的 **Nous Research Hermes Agent** 设计的 Android 移动客户端。

---

## 🌟 核心特性

1. **远程网关直连 (Remote Gateway)**：
   - 兼容 Hermes 桌面端协议，直连 Linux 服务器上的 Hermes Dashboard 服务（默认端口 `9119`）。
   - 支持 REST API 拉取历史会话 + WebSocket 实时全双工流式对话（`/api/ws`）。
2. **移动端深度思考折叠 (`ThinkingBubble`)**：
   - 针对手机小屏幕优化，大段模型推理推导过程默认收起为简洁状态指示，支持点击随时展开查验。
3. **工具执行可视化 (`ToolCard`)**：
   - 实时呈现 Hermes 在 Linux 服务器上执行的系统级工具（Bash、Web 搜索、Python 执行、文件读写等），附带参数与执行输出。
4. **会话云端漫游 (`SessionDrawer`)**：
   - 电脑端发起的研究任务，手机端抽屉一键同步接力。
5. **弱网自动重连与心跳保活**：
   - 适配移动网络 4G/5G/Wi-Fi 切换，断线后定时重连。

---

## 🚀 快速启动指南

### 1. Linux 服务器端启动网关
在部署了 Hermes Agent 的 Linux 服务器上运行：
```bash
# 启动仪表盘与网关服务
hermes dashboard --host 0.0.0.0 --port 9119
```
*提示：如果是内网或家庭云主机，建议使用 Tailscale 虚拟局域网（无需映射端口直接使用 100.x.x.x 内网 IP），或通过 Nginx 配置 SSL 反向代理。*

### 2. 手机端运行与打包
确保开发机已安装 Flutter SDK (>=3.2.0)：
```bash
# 进入工程目录
cd hermes-mobile

# 安装依赖
flutter pub get

# 调试运行 (连接真机或模拟器)
flutter run

# 打包发布 Release APK
flutter build apk --release
```
编译产物位于 `build/app/outputs/flutter-apk/app-release.apk`。

### 3. 配置网关连接
首次打开 App：
1. 点击右上角 **设置图标**（齿轮）。
2. 输入您的 Linux 服务器地址（例如 `http://192.168.1.100:9119` 或 Tailscale 域名/IP）。
3. 如设置了鉴权 Token，填入后点击 **“测试连接”**，确认成功后点击 **“保存并重连”**。


## 当前版本说明

- 历史消息默认加载最近 100 条，可在会话顶部继续加载更早的消息。
- 会话恢复支持 Hermes Dashboard 的 JSON-RPC 事件，同时保留原有消息格式的兼容处理。不同 Hermes 版本和网关配置仍需实际联调。
- 本项目默认使用调试签名构建 release APK，仅供测试；正式发布应配置自己的签名密钥。不同签名的安装包无法直接覆盖安装。
- 运行 `flutter analyze` 和 `flutter test` 检查代码及模拟网关测试。
