---
name: kb-python
description: Pythonのナレッジベース。型ヒント、パターン、ライブラリの使い方を蓄積
user-invocable: true
entry_count: 8
last_updated: 2026-03-31
last_updated: 2025-02-13
version_sensitive_entries:
  - "Pydantic BaseSettings: pydantic v2"
  - "psycopg3 ConnectionPool設定: psycopg 3.x"
---

# Python ナレッジベース

Pythonで学んだパターン、ベストプラクティス、トラブルシューティングを記録する。

## 型ヒント・型定義

（学んだ型ヒントパターンをここに追記）

## ベストプラクティス

### print文をloggerに統一する

**状況**: 開発中にprint文を使い、そのまま残ってしまう
**解決策**: 最初からlogging.getLogger(__name__)を使う。絵文字もログに含めない

```python
import logging
logger = logging.getLogger(__name__)

# NG
print("🚀 API起動中...")

# OK
logger.info("API起動中... モデルをウォームアップします")
```

### Pydantic BaseSettingsでの環境変数バリデーション

**状況**: 本番環境でデフォルト値（弱いパスワード等）が使われるリスク
**解決策**: `model_validator(mode="after")`で環境別バリデーションを実装

```python
class Settings(BaseSettings):
    app_env: str = "development"
    jwt_secret: str = "dev_secret"

    @model_validator(mode="after")
    def _validate_environment(self) -> "Settings":
        if self.app_env == "production":
            if self.jwt_secret in {"dev_secret", "changeme", ""}:
                raise ValueError("本番環境では安全なJWT_SECRETが必須です")
            if len(self.jwt_secret) < 32:
                raise ValueError("JWT_SECRETは32文字以上が必要です")
        return self
```

## ライブラリ活用

### psycopg3 ConnectionPool設定の環境変数化

**状況**: DB接続プールの設定がハードコードされていた
**解決策**: Pydantic Settingsで管理し、環境ごとに調整可能にする

```python
# config.py
db_pool_min_size: int = 2
db_pool_max_size: int = 10
db_pool_timeout: float = 30.0

# database.py
p = ConnectionPool(
    conninfo,
    min_size=settings.db_pool_min_size,
    max_size=settings.db_pool_max_size,
    timeout=settings.db_pool_timeout,
    kwargs={"row_factory": dict_row},
)
```

### feedparser でRSSをパースする
<!-- added: 2026-03-31 -->

**状況**: CDATA・名前空間付き要素（`content:encoded`）・RFC 2822日付を含むRSSフィードをパースしたい
**解決策**: `feedparser` を使う。これらすべてを自動処理してくれるため、手動での XML 解析が不要

```python
import feedparser

feed = feedparser.parse("https://example.com/rss.xml")

for entry in feed.entries:
    guid  = entry.get("id", entry.get("link"))   # guid が無い場合は link で代替
    title = entry.title                           # CDATA を自動アンラップ
    date  = entry.get("published", "")            # RFC 2822 文字列
    desc  = entry.get("description", "")          # content:encoded も取得可能

# feed.bozo=True でもエントリが取れれば継続可能（軽微な XML 不正は許容）
if feed.bozo and not feed.entries:
    raise RuntimeError(f"パース失敗: {feed.bozo_exception}")
```

### Discord Webhook Embed 送信の注意点
<!-- added: 2026-03-31 -->

**状況**: Discord Webhook に Embed 付きメッセージを送信すると 400 エラーや 429 エラーが発生する
**解決策**: サムネイル URL 長さチェックと 429 リトライの2点を必ず実装する

```python
import requests, time

def send_embed(webhook_url: str, embed: dict) -> None:
    # サムネイル URL が 2000 文字超だと 400 エラー → 事前に除外
    if "thumbnail" in embed and len(embed["thumbnail"]["url"]) >= 2000:
        del embed["thumbnail"]

    resp = requests.post(webhook_url, json={"embeds": [embed]}, timeout=30)

    if resp.status_code == 429:           # レート制限: 30 msg/min/Webhook
        retry_after = resp.json().get("retry_after", 5)
        time.sleep(retry_after)
        resp = requests.post(webhook_url, json={"embeds": [embed]}, timeout=30)

    resp.raise_for_status()
```

- Embed の各フィールド上限: `title` 256文字、`description` 4096文字、`footer.text` 2048文字
- 予防的に送信間隔を 2 秒空けると通常運用では 429 は発生しない

## トラブルシューティング

### macOSでpythonコマンドが使えない

**状況**: `python -m py_compile` で `command not found`
**解決策**: macOSでは `python3` を使用する。`python` コマンドはデフォルトでは存在しない

## Tips

### CORS設定は最小権限で

`allow_methods=["*"]`, `allow_headers=["*"]` は避け、必要なもののみ指定する

```python
app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_origins,
    allow_methods=["GET", "POST", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type"],
)
```
