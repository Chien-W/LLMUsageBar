#!/usr/bin/env python3
"""
AI API 用量监控 - 数据存储层
使用 SQLite 存储历史用量数据
"""
import sqlite3
import json
from datetime import datetime, timedelta
from pathlib import Path
from contextlib import contextmanager

DB_DIR = Path.home() / ".ai-api-monitor"
DB_FILE = DB_DIR / "usage.db"


def _ensure_db():
    DB_DIR.mkdir(parents=True, exist_ok=True)


@contextmanager
def get_db():
    _ensure_db()
    conn = sqlite3.connect(str(DB_FILE))
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()


def init_db():
    """初始化数据库表"""
    with get_db() as conn:
        conn.executescript("""
            CREATE TABLE IF NOT EXISTS usage_records (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                provider TEXT NOT NULL,         -- 'gemini' or 'zhipu'
                model TEXT NOT NULL,
                input_tokens INTEGER DEFAULT 0,
                output_tokens INTEGER DEFAULT 0,
                total_tokens INTEGER DEFAULT 0,
                cost REAL DEFAULT 0.0,
                currency TEXT DEFAULT 'USD',
                status TEXT DEFAULT 'success',  -- 'success' or 'error'
                recorded_at TEXT NOT NULL,
                raw_data TEXT                   -- JSON string for extra info
            );

            CREATE TABLE IF NOT EXISTS daily_summary (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                provider TEXT NOT NULL,
                date TEXT NOT NULL,             -- YYYY-MM-DD
                total_requests INTEGER DEFAULT 0,
                total_input_tokens INTEGER DEFAULT 0,
                total_output_tokens INTEGER DEFAULT 0,
                total_tokens INTEGER DEFAULT 0,
                total_cost REAL DEFAULT 0.0,
                success_count INTEGER DEFAULT 0,
                error_count INTEGER DEFAULT 0,
                model_breakdown TEXT,           -- JSON: {"model_name": {tokens, cost, count}}
                UNIQUE(provider, date)
            );

            CREATE TABLE IF NOT EXISTS quota_snapshots (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                provider TEXT NOT NULL,
                snapshot_at TEXT NOT NULL,
                balance REAL DEFAULT 0.0,
                used REAL DEFAULT 0.0,
                total_quota REAL DEFAULT 0.0,
                usage_percentage REAL DEFAULT 0.0,
                raw_data TEXT                   -- JSON
            );

            CREATE INDEX IF NOT EXISTS idx_records_provider_time
                ON usage_records(provider, recorded_at);
            CREATE INDEX IF NOT EXISTS idx_daily_provider_date
                ON daily_summary(provider, date);
            CREATE INDEX IF NOT EXISTS idx_quota_provider_time
                ON quota_snapshots(provider, snapshot_at);
        """)


def insert_usage_record(provider, model, input_tokens, output_tokens, cost,
                        currency="USD", status="success", raw_data=None):
    """插入一条使用记录"""
    total = input_tokens + output_tokens
    with get_db() as conn:
        conn.execute("""
            INSERT INTO usage_records 
            (provider, model, input_tokens, output_tokens, total_tokens, cost, currency, status, recorded_at, raw_data)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (provider, model, input_tokens, output_tokens, total, cost, currency, status,
              datetime.now().isoformat(), json.dumps(raw_data) if raw_data else None))


def upsert_daily_summary(provider, date_str, requests=0, input_tokens=0,
                         output_tokens=0, cost=0.0, success=0, error=0,
                         model_breakdown=None):
    """插入或更新每日汇总"""
    total = input_tokens + output_tokens
    with get_db() as conn:
        conn.execute("""
            INSERT INTO daily_summary 
            (provider, date, total_requests, total_input_tokens, total_output_tokens, 
             total_tokens, total_cost, success_count, error_count, model_breakdown)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(provider, date) DO UPDATE SET
                total_requests = excluded.total_requests,
                total_input_tokens = excluded.total_input_tokens,
                total_output_tokens = excluded.total_output_tokens,
                total_tokens = excluded.total_tokens,
                total_cost = excluded.total_cost,
                success_count = excluded.success_count,
                error_count = excluded.error_count,
                model_breakdown = excluded.model_breakdown
        """, (provider, date_str, requests, input_tokens, output_tokens,
              total, cost, success, error,
              json.dumps(model_breakdown) if model_breakdown else None))


def insert_quota_snapshot(provider, balance, used, total_quota, percentage, raw_data=None):
    """插入配额快照"""
    with get_db() as conn:
        conn.execute("""
            INSERT INTO quota_snapshots 
            (provider, snapshot_at, balance, used, total_quota, usage_percentage, raw_data)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        """, (provider, datetime.now().isoformat(), balance, used, total_quota,
              percentage, json.dumps(raw_data) if raw_data else None))


def get_daily_summary(days=30):
    """获取最近N天的每日汇总"""
    start_date = (datetime.now() - timedelta(days=days)).strftime("%Y-%m-%d")
    with get_db() as conn:
        rows = conn.execute("""
            SELECT * FROM daily_summary 
            WHERE date >= ? 
            ORDER BY date ASC
        """, (start_date,)).fetchall()
        return [dict(r) for r in rows]


def get_recent_records(limit=50, offset=0):
    """获取最近的使用记录"""
    with get_db() as conn:
        rows = conn.execute("""
            SELECT * FROM usage_records 
            ORDER BY recorded_at DESC 
            LIMIT ? OFFSET ?
        """, (limit, offset)).fetchall()
        total = conn.execute("SELECT COUNT(*) FROM usage_records").fetchone()[0]
        return [dict(r) for r in rows], total


def get_latest_quota(provider):
    """获取某个提供商的最新配额快照"""
    with get_db() as conn:
        row = conn.execute("""
            SELECT * FROM quota_snapshots 
            WHERE provider = ? 
            ORDER BY snapshot_at DESC 
            LIMIT 1
        """, (provider,)).fetchone()
        return dict(row) if row else None


def get_today_summary(provider):
    """获取今日的汇总数据"""
    today = datetime.now().strftime("%Y-%m-%d")
    with get_db() as conn:
        row = conn.execute("""
            SELECT * FROM daily_summary 
            WHERE provider = ? AND date = ?
        """, (provider, today)).fetchone()
        return dict(row) if row else None


def get_model_distribution(days=30):
    """获取模型使用分布"""
    start_date = (datetime.now() - timedelta(days=days)).strftime("%Y-%m-%d")
    with get_db() as conn:
        rows = conn.execute("""
            SELECT provider, model, 
                   COUNT(*) as count,
                   SUM(total_tokens) as tokens,
                   SUM(cost) as cost
            FROM usage_records 
            WHERE recorded_at >= ?
            GROUP BY provider, model
            ORDER BY tokens DESC
        """, (start_date,)).fetchall()
        return [dict(r) for r in rows]
