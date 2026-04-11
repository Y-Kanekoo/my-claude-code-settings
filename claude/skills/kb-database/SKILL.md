---
name: kb-database
description: データベースのナレッジベース。SQL/NoSQL、ORM、クエリ最適化を蓄積
user-invocable: true
entry_count: 6
last_updated: 2025-02-13
version_sensitive_entries:
  - "psycopg3 ConnectionPool: psycopg 3.x"
---

# データベース ナレッジベース

SQL/NoSQL、ORM、クエリ最適化で学んだパターンを記録する。

## SQL パターン

### マイグレーションのカラム名一貫性チェック

**状況**: テーブル定義では`provider_subject`だがインデックス定義では`subject`と記述してしまった
**解決策**: インデックス作成時は必ずテーブル定義のカラム名と照合する

```sql
-- テーブル定義を確認
-- CREATE TABLE auth_identities (provider_subject text NOT NULL);

-- インデックスはカラム名と一致させる
CREATE INDEX idx_auth_identities_provider_subject
    ON auth_identities (provider, provider_subject);  -- subjectではなくprovider_subject
```

## NoSQL

（MongoDB、DynamoDB等のパターンをここに追記）

## ORM

### psycopg3 ConnectionPoolのリトライパターン

```python
def _create_pool() -> ConnectionPool:
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            return ConnectionPool(conninfo, min_size=2, max_size=10, timeout=30.0,
                                  kwargs={"row_factory": dict_row})
        except Exception as e:
            if attempt < MAX_RETRIES:
                logger.warning("接続失敗(%d/%d): %s", attempt, MAX_RETRIES, e)
                time.sleep(RETRY_INTERVAL)
            else:
                raise
```

## パフォーマンス

### 複合インデックスの設計指針

ユーザーIDでフィルタ + 日時でソートするクエリには複合インデックスが有効

```sql
-- WHERE user_id = ? ORDER BY created_at DESC のクエリ用
CREATE INDEX idx_sessions_user_created
    ON user_sessions (user_id, created_at DESC);
```

### GINインデックスで配列検索を高速化

```sql
-- text[]型カラムの検索用
CREATE INDEX idx_knowledge_cards_symptom_tags
    ON knowledge_cards USING GIN (symptom_tags);
```

## トラブルシューティング

（遭遇した問題と解決策をここに追記）

## Tips

### snake_case ⇔ camelCase変換の一貫性

DB(snake_case) → Python models.py(camelCase) → TypeScript(camelCase) の変換を手動で行う場合、変換漏れに注意。auth.pyの`get_user_with_settings()`のような変換関数を1箇所に集約すると保守性が向上する
