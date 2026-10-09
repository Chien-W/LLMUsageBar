# 🌟 LLMUsageBar (AI 用量监控 · macOS 菜单栏原生应用)

一款参考 GitHub 热门开源菜单栏工具（如 Stats、Ice、ClaudeBar）设计的 **macOS 原生菜单栏 (Menu Bar) 工具**。专为开发者打造，实时监控 **Google Gemini** 与 **智谱 AI (zai)** 的 API 配额与用量。

---

## ✨ 核心特性

- 🖥 **原生 macOS 体验**：使用纯原生 Swift + SwiftUI + AppKit 开发，体积仅 **~890 KB**，毫秒级响应，内存占用极低（~15MB），无 Electron/Webview 臃肿负担。
- 🪄 **状态栏常驻**：常驻屏幕右上角菜单栏，支持 SF Symbol 图标，可切换“仅图标”、“智谱额度%”、“状态在线圆点”等展示模式。
- 🔮 **现代毛玻璃 UI (Vibrant Popover)**：
  - 点击菜单栏图标即刻呼出精美悬浮面板，采用 macOS 原生 Material 毛玻璃质感与圆角卡片设计。
  - 暗色 / 浅色模式全自适应。
- ⚡️ **智谱 AI (zai / GLM)** 监控：
  - 直连官方配额端点，支持 Coding Plan 5小时滑动窗口 / 周度额度监控。
  - 动态圆环进度条（Circular Progress Ring）与 Token 消耗统计。
  - 内置 GLM-4-Plus、GLM-4-Air、GLM-4-Flash 等主流模型定价参考速查。
- 💎 **Google Gemini** 监控：
  - 连通性测试与毫秒级延迟探测。
  - 自动获取项目可用模型清单。
  - 内置 Gemini 2.5 Pro / Flash、Gemini 2.0 Flash 等最新主流模型定价指南与官方控制台一键直达。
- ⚙️ **配置与安全**：
  - API Key 安全本地持久化，支持密码显隐切换与一键连通性测试。
  - 支持自定义后台自动刷新频率（1分钟 / 3分钟 / 5分钟 / 15分钟）。
  - 支持右键快捷菜单（立即刷新、偏好设置、退出）。

---

## 🚀 快速启动与安装

### 方式 1：一键安装到应用程序（推荐）
在终端中执行：
```bash
./install.sh
```
该脚本会自动完成编译，并将 `LLMUsageBar.app` 安装到系统的 `/Applications`（应用程序）目录，同时直接启动它！

### 方式 2：本地编译并直接运行
```bash
./build.sh
open build/LLMUsageBar.app
```

---

## 💡 使用指南

1. **呼出面板**：
   - 点击屏幕右上角菜单栏的 **✨ (闪烁星标)** 图标，即可弹出悬浮监控面板。
2. **初次配置**：
   - 点击面板顶部的 **⚙️ 设置**（或右键菜单栏图标选择“偏好设置”）。
   - 分别输入你的：
     - **智谱 (zai) API Key**（在 [智谱开放平台](https://open.bigmodel.cn/usercenter/apikeys) 获取）
     - **Google Gemini API Key**（在 [Google AI Studio](https://aistudio.google.com/apikey) 获取）
   - 点击旁边的 **测试** 按钮验证连通性，然后点击 **保存配置**。
3. **右键快捷操作**：
   - 鼠标右键点击菜单栏图标，可弹出快速菜单：支持 **立即刷新**、**偏好设置** 与 **退出程序**。

---

## 🛠 技术架构

```
LLMUsageBar/
├── App/
│   ├── AppDelegate.swift    # 状态栏图标 (NSStatusItem) 与 Popover 生命周期管理
│   └── main.swift           # 原生应用入口
├── Models/
│   ├── AppState.swift       # 全局响应式状态与后台轮询定时器
│   └── ConfigManager.swift  # 本地持久化配置中心
├── Services/
│   ├── GeminiService.swift  # Google Gemini API 连通性探测与模型清单检索
│   └── ZhipuService.swift   # 智谱 JWT 规范签名与配额接口查询
└── Views/
    ├── MenuBarView.swift     # 悬浮面板主框架 (Navigation & TabBar)
    ├── OverviewView.swift    # 双模型监控综合卡片与圆环进度条
    ├── ZhipuDetailView.swift # 智谱额度与套餐用量详情
    ├── GeminiDetailView.swift# Gemini 延迟分析与定价参考
    ├── SettingsView.swift    # API Key 配置与显示模式设置
    └── Components/
        └── CircularProgressView.swift # 矢量圆环进度组件
```
