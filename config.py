#!/usr/bin/env python3
"""
AI API 用量监控 - 配置管理
"""
import os
import json
from pathlib import Path
from cryptography.fernet import Fernet

CONFIG_DIR = Path.home() / ".ai-api-monitor"
CONFIG_FILE = CONFIG_DIR / "config.json"
KEY_FILE = CONFIG_DIR / ".key"


def _get_or_create_key() -> bytes:
    """获取或创建加密密钥"""
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    if KEY_FILE.exists():
        return KEY_FILE.read_bytes()
    key = Fernet.generate_key()
    KEY_FILE.write_bytes(key)
    os.chmod(str(KEY_FILE), 0o600)
    return key


def _encrypt(value: str) -> str:
    if not value:
        return ""
    f = Fernet(_get_or_create_key())
    return f.encrypt(value.encode()).decode()


def _decrypt(value: str) -> str:
    if not value:
        return ""
    try:
        f = Fernet(_get_or_create_key())
        return f.decrypt(value.encode()).decode()
    except Exception:
        return ""


def load_config() -> dict:
    """加载配置"""
    default = {
        "gemini_api_key": "",
        "zhipu_api_key": "",
        "refresh_interval": 60,
        "gemini_project_id": "",
    }
    if not CONFIG_FILE.exists():
        return default
    try:
        with open(CONFIG_FILE, "r") as f:
            data = json.load(f)
        # 解密 API keys
        if data.get("gemini_api_key"):
            data["gemini_api_key"] = _decrypt(data["gemini_api_key"])
        if data.get("zhipu_api_key"):
            data["zhipu_api_key"] = _decrypt(data["zhipu_api_key"])
        return {**default, **data}
    except Exception:
        return default


def save_config(config: dict):
    """保存配置（API Key 加密存储）"""
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    data = dict(config)
    # 加密 API keys
    if data.get("gemini_api_key"):
        data["gemini_api_key"] = _encrypt(data["gemini_api_key"])
    if data.get("zhipu_api_key"):
        data["zhipu_api_key"] = _encrypt(data["zhipu_api_key"])
    with open(CONFIG_FILE, "w") as f:
        json.dump(data, f, indent=2)
    os.chmod(str(CONFIG_FILE), 0o600)


def mask_key(key: str) -> str:
    """遮蔽 API Key，仅显示前4后4位"""
    if not key or len(key) < 10:
        return "未设置"
    return key[:4] + "*" * (len(key) - 8) + key[-4:]
