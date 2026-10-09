# 🌟 LLMUsageBar (AI 用量监控 · macOS 菜单栏原生应用)

一款参考 GitHub 热门开源菜单栏工具（如 Stats、Ice、ClaudeBar）设计的 **macOS 原生菜单栏 (Menu Bar) 工具**。专为开发者打造，实时监控 **Google Gemini**、**Anthropic Claude** 与 **智谱 AI (BigModel)** 的 API 配额与真实用量。

---

## ✨ 核心特性

- 🖥 **原生 macOS 体验**：使用纯原生 Swift + SwiftUI + AppKit 开发，体积仅 **~900 KB**，毫秒级响应，内存占用极低（~15MB），无 Electron 臃肿负担。
- 🪄 **状态栏常驻与便捷交互**：
  - 常驻屏幕右上角菜单栏，支持 SF Symbol 图标。
  - **点击外部自动收起**：点击桌面任意空白处或切换其他应用窗口时，面板自动收起；点击图标切换自带防抖保护。
  - 支持右键快捷菜单（立即刷新全部、添加账号、设置、退出）。
- 👥 **多账号与多模型统一管理**：
  - 一个账号卡片统一展示该账号下的所有模型额度（避免按模型切碎账号）。
  - 支持快捷开启/关闭单个账号监控，直观展示实时连通状态与刷新倒计时。
- ⚡️ **真实用量本地/云端实时同步**：
  - **Antigravity 本地 IDE 极速 RPC 同步**：0.09s 毫秒级直连本地 Language Server，精准获取 Google Gemini (2.5 Pro / Flash) 与 Anthropic Claude (Opus 4 / Sonnet 4) 的真实剩余额度与重置时间倒计时。
  - **智谱 AI (BigModel / Coding Plan)**：精准解析 5小时滑动窗口额度、周度额度与 MCP 工具调用额度，与官网个人中心完全一致。
- 🔮 **现代设计与深浅主题自适应**：
  - 原生跟随 macOS 系统深浅色外观切换，高对比度排版，清晰易读。
- ⚙️ **配置与安全**：
  - API Key 仅保存在本机 UserDefaults，敏感信息前端支持显隐切换与一键连通性测试。
  - 支持自定义后台自动刷新频率（1分钟 / 3分钟 / 5分钟 / 15分钟）。

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
   - 点击桌面任意空白处即可自动收起。
2. **添加与管理账号**：
   - 点击面板顶部的 **「账号」** 或右上角的 **「+」** 加号。
   - 输入账号名称与 API Key，点击 **「测试连接」** 验证无误后即可保存启用。
3. **右键快捷操作**：
   - 鼠标右键点击菜单栏图标，可弹出快速菜单：支持 **立即刷新全部**、**添加新账号**、**管理账号** 与 **退出**。

---

## 🛠 项目架构

```
LLMUsageBar/
├── App/
│   ├── AppDelegate.swift    # 状态栏图标 (NSStatusItem)、Popover 与全局外部点击监听
│   └── main.swift           # 原生应用入口
├── Models/
│   ├── Account.swift        # 多账号与模型配额数据模型
│   ├── AppState.swift       # 全局响应式状态、定时轮询与数据同步调度
│   └── ConfigManager.swift  # 本地持久化配置中心
├── Services/
│   ├── LocalIDEService.swift# Antigravity 本地 IDE 极速 RPC 额度发现与同步
│   ├── ZhipuService.swift   # 智谱 BigModel 额度接口解析与连通测试
│   └── GeminiService.swift  # Gemini 官方接口服务
└── Views/
    ├── MenuBarView.swift     # 悬浮面板主框架 (Navigation & TabBar)
    ├── OverviewView.swift    # 综合概览视图
    ├── AccountsManageView.swift # 账号增删查改与 API Key 管理
    ├── SettingsView.swift    # 刷新间隔与显示模式偏好设置
    └── Components/
        ├── AccountCardView.swift      # 账号配额卡片（支持进度条与重置倒计时）
        └── CircularProgressView.swift # 矢量圆环进度组件
```

