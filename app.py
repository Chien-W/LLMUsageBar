#!/usr/bin/env python3
"""
AI API 用量监控 - Flask 主应用
"""
import os
import json
import random
from datetime import datetime, timedelta
from flask import Flask, render_template, jsonify, request
from apscheduler.schedulers.background import BackgroundScheduler

from config import load_config, save_config, mask_key
from storage import (
    init_db, get_daily_summary, get_recent_records,
    get_latest_quota, get_today_summary, get_model_distribution,
    insert_quota_snapshot, upsert_daily_summary, insert_usage_record
)
from providers import GeminiProvider, ZhipuProvider

app = Flask(__name__)
scheduler = BackgroundScheduler(daemon=True)

# 全局状态
_status = {
    "gemini": {"connected": False, "message": "未连接", "last_check": None},
    "zhipu": {"connected": False, "message": "未连接", "last_check": None},
    "last_refresh": None,
}


def _get_provider(name: str):
    """获取 API 提供商实例"""
    config = load_config()
    if name == "gemini" and config.get("gemini_api_key"):
        return GeminiProvider(config["gemini_api_key"])
    elif name == "zhipu" and config.get("zhipu_api_key"):
        return ZhipuProvider(config["zhipu_api_key"])
    return None


def refresh_data():
    """刷新所有提供商的数据"""
    global _status
    config = load_config()
    now = datetime.now()

    # ---- Gemini ----
    if config.get("gemini_api_key"):
        try:
            provider = GeminiProvider(config["gemini_api_key"])
            quota = provider.get_quota_info()
            _status["gemini"] = {
                "connected": quota.get("connected", False),
                "message": quota.get("message", ""),
                "last_check": now.isoformat(),
                "models": quota.get("models", []),
            }
            if quota.get("connected"):
                insert_quota_snapshot(
                    "gemini",
                    balance=quota.get("balance", -1),
                    used=0,
                    total_quota=0,
                    percentage=0,
                    raw_data=quota
                )
        except Exception as e:
            _status["gemini"] = {
                "connected": False,
                "message": f"刷新失败: {str(e)}",
                "last_check": now.isoformat(),
            }
    else:
        _status["gemini"] = {
            "connected": False,
            "message": "API Key 未设置",
            "last_check": now.isoformat(),
        }

    # ---- 智谱 ----
    if config.get("zhipu_api_key"):
        try:
            provider = ZhipuProvider(config["zhipu_api_key"])
            quota = provider.get_quota_info()
            _status["zhipu"] = {
                "connected": quota.get("connected", False),
                "message": quota.get("message", ""),
                "last_check": now.isoformat(),
                "balance": quota.get("balance", 0),
                "used": quota.get("used", 0),
                "total": quota.get("total", 0),
                "usage_percentage": quota.get("usage_percentage", 0),
                "level": quota.get("level", ""),
            }
            if quota.get("connected"):
                insert_quota_snapshot(
                    "zhipu",
                    balance=quota.get("balance", 0),
                    used=quota.get("used", 0),
                    total_quota=quota.get("total", 0),
                    percentage=quota.get("usage_percentage", 0),
                    raw_data=quota
                )
        except Exception as e:
            _status["zhipu"] = {
                "connected": False,
                "message": f"刷新失败: {str(e)}",
                "last_check": now.isoformat(),
            }
    else:
        _status["zhipu"] = {
            "connected": False,
            "message": "API Key 未设置",
            "last_check": now.isoformat(),
        }

    _status["last_refresh"] = now.isoformat()


def _generate_demo_data():
    """生成演示数据，让 Dashboard 在没有真实 API Key 时也能展示效果"""
    now = datetime.now()
    models_gemini = ["gemini-2.5-pro", "gemini-2.5-flash", "gemini-2.0-flash"]
    models_zhipu = ["glm-4-plus", "glm-4-flash", "glm-4-air"]

    for i in range(30):
        date = (now - timedelta(days=29 - i)).strftime("%Y-%m-%d")
        # Gemini 每日数据
        g_input = random.randint(50000, 500000)
        g_output = random.randint(20000, 200000)
        g_reqs = random.randint(20, 200)
        g_errors = random.randint(0, 5)
        g_model = random.choice(models_gemini)
        g_cost = GeminiProvider.calc_cost(g_model, g_input, g_output)
        g_breakdown = {}
        for m in models_gemini:
            mt = random.randint(10000, 150000)
            g_breakdown[m] = {"tokens": mt, "cost": GeminiProvider.calc_cost(m, mt // 2, mt // 2), "count": random.randint(5, 50)}
        upsert_daily_summary("gemini", date, g_reqs, g_input, g_output, g_cost, g_reqs - g_errors, g_errors, g_breakdown)

        # 智谱每日数据
        z_input = random.randint(30000, 300000)
        z_output = random.randint(15000, 150000)
        z_reqs = random.randint(15, 150)
        z_errors = random.randint(0, 3)
        z_model = random.choice(models_zhipu)
        z_cost = ZhipuProvider.calc_cost(z_model, z_input, z_output)
        z_breakdown = {}
        for m in models_zhipu:
            mt = random.randint(8000, 120000)
            z_breakdown[m] = {"tokens": mt, "cost": ZhipuProvider.calc_cost(m, mt // 2, mt // 2), "count": random.randint(3, 40)}
        upsert_daily_summary("zhipu", date, z_reqs, z_input, z_output, z_cost, z_reqs - z_errors, z_errors, z_breakdown)

    # 生成最近的使用记录
    statuses = ["success"] * 9 + ["error"]
    for i in range(100):
        ts = now - timedelta(minutes=random.randint(0, 4320))
        provider = random.choice(["gemini", "zhipu"])
        model = random.choice(models_gemini if provider == "gemini" else models_zhipu)
        inp = random.randint(100, 50000)
        out = random.randint(50, 20000)
        status = random.choice(statuses)
        if provider == "gemini":
            cost = GeminiProvider.calc_cost(model, inp, out)
        else:
            cost = ZhipuProvider.calc_cost(model, inp, out)
        currency = "USD" if provider == "gemini" else "CNY"
        insert_usage_record(provider, model, inp, out, cost, currency, status)

    # 配额快照
    insert_quota_snapshot("gemini", balance=-1, used=0, total_quota=0, percentage=0)
    insert_quota_snapshot("zhipu", balance=7528, used=2472, total_quota=10000, percentage=25)


# ============================================================
# 路由
# ============================================================

@app.route("/")
def index():
    return render_template("index.html")


@app.route("/api/status")
def api_status():
    return jsonify({
        "gemini": _status.get("gemini", {}),
        "zhipu": _status.get("zhipu", {}),
        "last_refresh": _status.get("last_refresh"),
    })


@app.route("/api/usage/summary")
def api_usage_summary():
    """获取用量摘要（卡片数据）"""
    gemini_today = get_today_summary("gemini") or {}
    zhipu_today = get_today_summary("zhipu") or {}
    gemini_quota = get_latest_quota("gemini")
    zhipu_quota = get_latest_quota("zhipu")

    return jsonify({
        "gemini": {
            "today_requests": gemini_today.get("total_requests", 0),
            "today_tokens": gemini_today.get("total_tokens", 0),
            "today_input_tokens": gemini_today.get("total_input_tokens", 0),
            "today_output_tokens": gemini_today.get("total_output_tokens", 0),
            "today_cost": round(gemini_today.get("total_cost", 0), 4),
            "balance": gemini_quota.get("balance", -1) if gemini_quota else -1,
            "usage_percentage": gemini_quota.get("usage_percentage", 0) if gemini_quota else 0,
            "currency": "USD",
        },
        "zhipu": {
            "today_requests": zhipu_today.get("total_requests", 0),
            "today_tokens": zhipu_today.get("total_tokens", 0),
            "today_input_tokens": zhipu_today.get("total_input_tokens", 0),
            "today_output_tokens": zhipu_today.get("total_output_tokens", 0),
            "today_cost": round(zhipu_today.get("total_cost", 0), 4),
            "balance": zhipu_quota.get("balance", 0) if zhipu_quota else 0,
            "used": zhipu_quota.get("used", 0) if zhipu_quota else 0,
            "total": zhipu_quota.get("total_quota", 0) if zhipu_quota else 0,
            "usage_percentage": zhipu_quota.get("usage_percentage", 0) if zhipu_quota else 0,
            "currency": "CNY",
        }
    })


@app.route("/api/usage/daily")
def api_usage_daily():
    """获取每日趋势数据"""
    days = request.args.get("days", 30, type=int)
    data = get_daily_summary(days)
    return jsonify(data)


@app.route("/api/usage/models")
def api_usage_models():
    """获取模型使用分布"""
    days = request.args.get("days", 30, type=int)
    data = get_model_distribution(days)
    return jsonify(data)


@app.route("/api/usage/records")
def api_usage_records():
    """获取最近的使用记录"""
    limit = request.args.get("limit", 20, type=int)
    offset = request.args.get("offset", 0, type=int)
    records, total = get_recent_records(limit, offset)
    return jsonify({"records": records, "total": total, "limit": limit, "offset": offset})


@app.route("/api/settings", methods=["GET"])
def api_get_settings():
    """获取设置（API Key 已遮蔽）"""
    config = load_config()
    return jsonify({
        "gemini_api_key": mask_key(config.get("gemini_api_key", "")),
        "zhipu_api_key": mask_key(config.get("zhipu_api_key", "")),
        "refresh_interval": config.get("refresh_interval", 60),
        "gemini_api_key_set": bool(config.get("gemini_api_key")),
        "zhipu_api_key_set": bool(config.get("zhipu_api_key")),
    })


@app.route("/api/settings", methods=["POST"])
def api_save_settings():
    """保存设置"""
    data = request.get_json()
    config = load_config()

    # 只有非空且不是遮蔽值才更新
    if data.get("gemini_api_key") and "****" not in data["gemini_api_key"]:
        config["gemini_api_key"] = data["gemini_api_key"].strip()
    if data.get("zhipu_api_key") and "****" not in data["zhipu_api_key"]:
        config["zhipu_api_key"] = data["zhipu_api_key"].strip()
    if data.get("refresh_interval"):
        config["refresh_interval"] = max(10, int(data["refresh_interval"]))

    save_config(config)

    # 重新调度定时刷新
    _reschedule_refresh(config.get("refresh_interval", 60))
    # 立即刷新一次
    refresh_data()

    return jsonify({"success": True, "message": "设置已保存"})


@app.route("/api/test-connection", methods=["POST"])
def api_test_connection():
    """测试 API 连接"""
    data = request.get_json()
    provider_name = data.get("provider")
    api_key = data.get("api_key", "").strip()

    if not api_key or "****" in api_key:
        # 用已保存的 key
        config = load_config()
        api_key = config.get(f"{provider_name}_api_key", "")

    if not api_key:
        return jsonify({"success": False, "message": "请先输入 API Key"})

    if provider_name == "gemini":
        provider = GeminiProvider(api_key)
    elif provider_name == "zhipu":
        provider = ZhipuProvider(api_key)
    else:
        return jsonify({"success": False, "message": "未知的提供商"})

    result = provider.test_connection()
    return jsonify({
        "success": result.get("connected", False),
        "message": result.get("message", "未知结果")
    })


@app.route("/api/refresh", methods=["POST"])
def api_refresh():
    """手动刷新数据"""
    refresh_data()
    return jsonify({"success": True, "message": "数据已刷新", "last_refresh": _status.get("last_refresh")})


def _reschedule_refresh(interval: int):
    """重新调度定时刷新任务"""
    job = scheduler.get_job("refresh_job")
    if job:
        job.reschedule(trigger="interval", seconds=interval)
    else:
        scheduler.add_job(refresh_data, "interval", seconds=interval, id="refresh_job",
                          replace_existing=True)


def main():
    """主入口"""
    init_db()

    # 检查是否有历史数据，没有则生成演示数据
    records, total = get_recent_records(1)
    if total == 0:
        print("📊 首次运行，生成演示数据...")
        _generate_demo_data()

    config = load_config()
    interval = config.get("refresh_interval", 60)

    # 启动定时刷新
    _reschedule_refresh(interval)
    scheduler.start()

    # 启动时刷新一次
    refresh_data()

    port = int(os.environ.get("PORT", 5088))
    print(f"""
╔══════════════════════════════════════════════════════╗
║           🧠 AI API 用量监控 Dashboard               ║
║                                                      ║
║   🌐 打开浏览器访问: http://localhost:{port}            ║
║   📊 自动刷新间隔: {interval} 秒                        ║
║   ⌨️  按 Ctrl+C 停止服务                              ║
╚══════════════════════════════════════════════════════╝
    """)

    app.run(host="127.0.0.1", port=port, debug=False)


if __name__ == "__main__":
    main()
