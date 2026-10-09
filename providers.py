#!/usr/bin/env python3
"""
AI API 用量监控 - API 提供商客户端
支持 Google Gemini 和 智谱AI (Zhipu)
"""
import time
import json
import hashlib
import hmac
import requests
from datetime import datetime, timedelta
from typing import Optional

# ============================================================
# Gemini API 价格表 (USD per 1M tokens) - 2025/2026
# ============================================================
GEMINI_PRICING = {
    "gemini-2.5-pro": {"input": 1.25, "output": 10.00},
    "gemini-2.5-flash": {"input": 0.15, "output": 3.50},
    "gemini-2.0-flash": {"input": 0.10, "output": 0.40},
    "gemini-2.0-flash-lite": {"input": 0.075, "output": 0.30},
    "gemini-1.5-pro": {"input": 1.25, "output": 5.00},
    "gemini-1.5-flash": {"input": 0.075, "output": 0.30},
    "default": {"input": 0.15, "output": 0.60},
}

# ============================================================
# 智谱 AI 价格表 (CNY per 1M tokens)
# ============================================================
ZHIPU_PRICING = {
    "glm-4-plus": {"input": 50.0, "output": 50.0},
    "glm-4": {"input": 100.0, "output": 100.0},
    "glm-4-long": {"input": 1.0, "output": 1.0},
    "glm-4-air": {"input": 1.0, "output": 1.0},
    "glm-4-airx": {"input": 10.0, "output": 10.0},
    "glm-4-flash": {"input": 0.1, "output": 0.1},
    "glm-4-flashx": {"input": 0.1, "output": 0.1},
    "glm-4v": {"input": 50.0, "output": 50.0},
    "glm-4v-plus": {"input": 10.0, "output": 10.0},
    "glm-3-turbo": {"input": 1.0, "output": 1.0},
    "default": {"input": 1.0, "output": 1.0},
}


def _calc_cost(pricing_table: dict, model: str, input_tokens: int, output_tokens: int) -> float:
    """根据价格表计算费用"""
    key = model.lower()
    # 尝试精确匹配，然后前缀匹配
    prices = pricing_table.get(key)
    if not prices:
        for k, v in pricing_table.items():
            if k != "default" and key.startswith(k):
                prices = v
                break
    if not prices:
        prices = pricing_table["default"]
    cost = (input_tokens * prices["input"] + output_tokens * prices["output"]) / 1_000_000
    return round(cost, 6)


class GeminiProvider:
    """Google Gemini API 客户端"""

    BASE_URL = "https://generativelanguage.googleapis.com/v1beta"

    def __init__(self, api_key: str):
        self.api_key = api_key
        self.session = requests.Session()
        self.session.headers.update({"Content-Type": "application/json"})

    def test_connection(self) -> dict:
        """测试 API 连接"""
        try:
            url = f"{self.BASE_URL}/models?key={self.api_key}"
            resp = self.session.get(url, timeout=15)
            if resp.status_code == 200:
                data = resp.json()
                models = [m.get("name", "").replace("models/", "") for m in data.get("models", [])]
                return {
                    "connected": True,
                    "message": f"连接成功，发现 {len(models)} 个模型",
                    "models": models[:10]
                }
            else:
                return {
                    "connected": False,
                    "message": f"连接失败: HTTP {resp.status_code} - {resp.text[:200]}"
                }
        except Exception as e:
            return {"connected": False, "message": f"连接错误: {str(e)}"}

    def list_models(self) -> list:
        """列出可用模型"""
        try:
            url = f"{self.BASE_URL}/models?key={self.api_key}"
            resp = self.session.get(url, timeout=15)
            if resp.status_code == 200:
                return [m.get("name", "").replace("models/", "")
                        for m in resp.json().get("models", [])]
        except Exception:
            pass
        return []

    def get_usage_from_response_headers(self, model: str = "gemini-2.0-flash") -> Optional[dict]:
        """
        通过发送一个最小请求来获取使用统计（通过响应头和 usageMetadata）。
        Gemini API 没有独立的用量查询端点，但每次请求都会返回 token 使用信息。
        """
        try:
            url = f"{self.BASE_URL}/models/{model}:generateContent?key={self.api_key}"
            payload = {
                "contents": [{"parts": [{"text": "Hi"}]}],
                "generationConfig": {"maxOutputTokens": 5}
            }
            resp = self.session.post(url, json=payload, timeout=15)
            if resp.status_code == 200:
                data = resp.json()
                usage = data.get("usageMetadata", {})
                return {
                    "model": model,
                    "input_tokens": usage.get("promptTokenCount", 0),
                    "output_tokens": usage.get("candidatesTokenCount", 0),
                    "total_tokens": usage.get("totalTokenCount", 0),
                }
            return None
        except Exception:
            return None

    def get_quota_info(self) -> dict:
        """获取配额信息（通过 list models 推断连接状态）"""
        try:
            conn = self.test_connection()
            if conn["connected"]:
                return {
                    "provider": "gemini",
                    "connected": True,
                    "balance": -1,  # Gemini 按量付费，无固定余额
                    "status": "active",
                    "message": conn["message"],
                    "models": conn.get("models", [])
                }
            return {
                "provider": "gemini",
                "connected": False,
                "balance": 0,
                "status": "error",
                "message": conn["message"]
            }
        except Exception as e:
            return {
                "provider": "gemini",
                "connected": False,
                "balance": 0,
                "status": "error",
                "message": str(e)
            }

    @staticmethod
    def calc_cost(model: str, input_tokens: int, output_tokens: int) -> float:
        return _calc_cost(GEMINI_PRICING, model, input_tokens, output_tokens)


class ZhipuProvider:
    """智谱 AI API 客户端"""

    BASE_URL = "https://open.bigmodel.cn/api"
    CHAT_URL = f"{BASE_URL}/paas/v4/chat/completions"
    QUOTA_URL = f"{BASE_URL}/monitor/usage/quota/limit"
    BILL_URL = f"{BASE_URL}/paas/v4/billing/usage"

    def __init__(self, api_key: str):
        self.api_key = api_key
        self.session = requests.Session()

    def _get_auth_header(self) -> dict:
        """生成认证头（智谱API支持直接使用API Key）"""
        return {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json"
        }

    def _generate_jwt_token(self) -> str:
        """生成 JWT Token（智谱 API 的认证方式）"""
        import jwt
        try:
            parts = self.api_key.split(".")
            if len(parts) != 2:
                return self.api_key
            api_key_id, api_key_secret = parts
            now = int(time.time())
            payload = {
                "api_key": api_key_id,
                "exp": now + 3600,
                "timestamp": now
            }
            token = jwt.encode(
                payload,
                api_key_secret,
                algorithm="HS256",
                headers={"alg": "HS256", "sign_type": "SIGN"}
            )
            return token
        except Exception:
            return self.api_key

    def _get_jwt_header(self) -> dict:
        """使用 JWT 认证"""
        token = self._generate_jwt_token()
        return {
            "Authorization": token,
            "Content-Type": "application/json"
        }

    def test_connection(self) -> dict:
        """测试 API 连接"""
        try:
            headers = self._get_jwt_header()
            # 发送最小请求测试连接
            payload = {
                "model": "glm-4-flash",
                "messages": [{"role": "user", "content": "hi"}],
                "max_tokens": 5
            }
            resp = self.session.post(self.CHAT_URL, json=payload,
                                     headers=headers, timeout=15)
            if resp.status_code == 200:
                data = resp.json()
                usage = data.get("usage", {})
                return {
                    "connected": True,
                    "message": "连接成功",
                    "usage": usage
                }
            else:
                error_msg = resp.text[:200]
                try:
                    err = resp.json()
                    error_msg = err.get("error", {}).get("message", error_msg)
                except Exception:
                    pass
                return {
                    "connected": False,
                    "message": f"连接失败: {error_msg}"
                }
        except Exception as e:
            return {"connected": False, "message": f"连接错误: {str(e)}"}

    def get_quota_info(self) -> dict:
        """获取配额/余额信息"""
        try:
            headers = self._get_jwt_header()
            resp = self.session.get(self.QUOTA_URL, headers=headers, timeout=15)
            if resp.status_code == 200:
                data = resp.json()
                if data.get("success") or data.get("code") == 200:
                    limits_data = data.get("data", {})
                    limits = limits_data.get("limits", [])
                    token_limit = None
                    time_limit = None
                    for lim in limits:
                        if lim.get("type") == "TOKENS_LIMIT":
                            token_limit = lim
                        elif lim.get("type") == "TIME_LIMIT":
                            time_limit = lim

                    usage_pct = 0
                    remaining = 0
                    used = 0
                    total = 0

                    if token_limit:
                        usage_pct = token_limit.get("percentage", 0)
                        remaining = token_limit.get("remaining", 0)
                        used = token_limit.get("currentValue", 0)
                        total = token_limit.get("usage", 0)
                    elif time_limit:
                        usage_pct = time_limit.get("percentage", 0)
                        remaining = time_limit.get("remaining", 0)
                        used = time_limit.get("currentValue", 0)
                        total = time_limit.get("usage", 0)

                    return {
                        "provider": "zhipu",
                        "connected": True,
                        "balance": remaining,
                        "used": used,
                        "total": total,
                        "usage_percentage": usage_pct,
                        "level": limits_data.get("level", ""),
                        "status": "active",
                        "message": "获取配额成功",
                        "raw": data
                    }
                else:
                    return {
                        "provider": "zhipu",
                        "connected": True,
                        "balance": -1,
                        "status": "unknown",
                        "message": data.get("msg", "配额查询返回异常")
                    }
            # 如果配额接口失败，尝试用测试连接方式
            conn = self.test_connection()
            return {
                "provider": "zhipu",
                "connected": conn["connected"],
                "balance": -1,
                "status": "active" if conn["connected"] else "error",
                "message": conn["message"]
            }
        except Exception as e:
            return {
                "provider": "zhipu",
                "connected": False,
                "balance": 0,
                "status": "error",
                "message": str(e)
            }

    @staticmethod
    def calc_cost(model: str, input_tokens: int, output_tokens: int) -> float:
        return _calc_cost(ZHIPU_PRICING, model, input_tokens, output_tokens)
