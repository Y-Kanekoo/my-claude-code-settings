---
name: kb-docker
description: Docker/Kubernetesのナレッジベース。コンテナ設定、オーケストレーションを蓄積
user-invocable: true
entry_count: 6
last_updated: 2025-02-13
---

# Docker/Kubernetes ナレッジベース

Docker/Kubernetesで学んだパターン、設定方法、トラブルシューティングを記録する。

## Dockerfile パターン

### Python Dockerfile推奨ENV設定

```dockerfile
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
```

- `PYTHONDONTWRITEBYTECODE=1`: .pycファイルを生成しない（イメージサイズ削減）
- `PYTHONUNBUFFERED=1`: 標準出力をバッファしない（ログが即座に出力される）

### 非rootユーザーでの実行

```dockerfile
RUN useradd -m -u 10001 appuser && chown -R appuser:appuser /app
USER 10001
```

## Docker Compose

### サービスのヘルスチェックと依存関係

**状況**: MinIOが起動完了前にバケット初期化コンテナが実行されて失敗する
**解決策**: `healthcheck` + `depends_on: condition: service_healthy` を使う

```yaml
minio:
  image: minio/minio:latest
  restart: unless-stopped
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:9000/minio/health/live"]
    interval: 10s
    timeout: 5s
    retries: 5

mc:
  image: minio/mc:latest
  restart: "no"
  depends_on:
    minio:
      condition: service_healthy
```

### restart policyの使い分け

| ポリシー | 用途 |
|---------|------|
| `unless-stopped` | 永続サービス（DB, API, Worker等） |
| `"no"` | 初期化コンテナ（マイグレーション、バケット作成等） |
| `on-failure` | 一時的な障害で再起動したいバッチ |

### .dockerignoreの作成

各サービスディレクトリに `.dockerignore` を配置し、ビルドコンテキストを最小化する

```
.env
__pycache__
.pytest_cache
.coverage
.git
*.pyc
```

## Kubernetes

（K8sのマニフェスト、設定パターンをここに追記）

## トラブルシューティング

（遭遇した問題と解決策をここに追記）

## Tips

（便利なTipsをここに追記）
