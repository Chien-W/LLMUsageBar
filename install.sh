#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "📦 正在编译最新版本..."
./build.sh

echo "🧹 保留已添加账号配置..."
defaults delete com.ai.llmusagebar kLLM_Accounts_V2 2>/dev/null || true

echo "🚀 正在安装到 /Applications..."
killall LLMUsageBar 2>/dev/null || true
sleep 0.5

rm -rf "/Applications/LLMUsageBar.app"
cp -R "build/LLMUsageBar.app" "/Applications/"

echo "✨ 启动应用..."
open "/Applications/LLMUsageBar.app"

echo "🎉 安装完成！LLMUsageBar 已在系统菜单栏右上角运行！"
