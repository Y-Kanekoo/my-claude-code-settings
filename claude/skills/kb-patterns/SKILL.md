---
name: kb-patterns
description: 再利用可能な設計パターン集。アーキテクチャ、実装パターンを蓄積
user-invocable: true
entry_count: 12
last_updated: 2026-04-11
---

# 設計パターン ナレッジベース

技術分野を問わず、再利用可能な設計パターンを記録する。

## ハーネス設計ガイド
<!-- added: 2026-04-09 -->

### ハーネステンプレートの使い方

**テンプレート配置先**: `~/.claude/templates/harness/`

**設計方針**: 「最小から足す」（Codex gpt-5.4 + Claude Opus 4.6 合意）
- グローバル設定が厚いため、プロジェクトは**差分のみ**記述
- 最大構成から削る方式は重複・設定漂流・ゴミ権限の温床になる

**ティア構成**:

| ティア | 構成 | 昇格条件 |
|--------|------|----------|
| Tier 1（必須） | CLAUDE.md + settings.local.json | 全プロジェクト |
| Tier 2（標準） | + PostToolUseフック | PJ固有バリデーションが必要になった時 |
| Tier 3（フル） | + commands/ + agents/ | 同じ操作を2回以上手動指示した時 |

**CLAUDE.mdの7セクション構成**:
1. 目的・対象
2. 構成と責務（スタック・ディレクトリ）
3. 起動・テスト・デプロイ
4. このPJ固有の規約
5. 変更禁止・高リスク領域
6. 主要運用手順
7. 参照先

**自動改善ループの統合**: グローバルフックが全PJに適用済み。PJ固有の最適化は `検出ルール` `分類タグ` `閾値` `除外パターン` の上書きのみ行う。

**詳細**: `~/.claude/templates/harness/README.md` 参照

## アーキテクチャパターン

### AI向けコードベースガイドの設計

**状況**: Claude/Codexがコード修正時に参照する仕様書が必要
**解決策**: `docs/CODEBASE_GUIDE.md` として以下の構成で作成

1. 技術スタック一覧表（バージョン付き）
2. ファイルマップ（全ファイルのパス・役割・export一覧を表形式で）
3. 依存関係グラフ（テキスト形式）
4. 状態管理の詳細（Query Key一覧、staleTime設定等）
5. API⇔TypeScript型対応表（snake_case⇔camelCase変換ルール含む）
6. DB定義（テーブル・カラム・インデックス）
7. 開発時の制約・落とし穴（具体的なエラーと対処法）

**重要**: コード変更時はガイドも追従更新する

## 実装パターン

### ヘルスチェックの全コンポーネント反映

**状況**: `/health`エンドポイントがDB/Redisのみチェックし、MLモデル状態を無視していた
**解決策**: 全依存コンポーネントの状態をoverall healthに反映する

```python
model_status = get_model_status()
components["model"] = model_status
if not model_status.get("loaded"):
    overall_healthy = False

return {"status": "healthy" if overall_healthy else "degraded", "components": components}
```

## API設計

### FastAPI統一エラーレスポンス

全エラーを同一スキーマ `{code, message, details}` で返す

```python
@app.exception_handler(StarletteHTTPException)
async def http_exception_handler(request, exc):
    code_map = {400: "BAD_REQUEST", 401: "UNAUTHORIZED", 404: "NOT_FOUND", 500: "INTERNAL_ERROR"}
    return JSONResponse(status_code=exc.status_code, content={
        "code": code_map.get(exc.status_code, "ERROR"),
        "message": str(exc.detail),
        "details": None,
    })
```

### Proxyパターンによる後方互換DI
<!-- added: 2026-02-23 -->

**状況**: モジュールレベルで `settings = SettingsManager()` を公開していたが、テスト時にDI（差し替え）できない
**解決策**: `__getattr__` を使った Proxy クラスで後方互換を維持しつつ DI 可能にする

```python
_settings: Optional[SettingsManager] = None

def get_settings() -> SettingsManager:
    global _settings
    if _settings is None:
        _settings = SettingsManager()
    return _settings

def set_settings(instance: SettingsManager) -> None:
    """テスト用: インスタンスを差し替える"""
    global _settings
    _settings = instance

class _SettingsProxy:
    """bot_utils.settings.xxx → get_settings().xxx に委譲"""
    def __getattr__(self, name: str):
        return getattr(get_settings(), name)

settings = _SettingsProxy()  # 既存コードはそのまま動く
```

利用側は `from bot_utils import settings` のまま変更不要。テスト側で `set_settings(mock)` を呼ぶだけ。

### RSS → 外部サービス通知の状態管理
<!-- added: 2026-03-31 -->

**状況**: RSSフィードを定期チェックして外部サービス（Discord 等）に通知する際、重複送信を防ぎたい
**解決策**: 送信済み記事 ID を JSON ファイルでリポジトリ管理する

```json
// data/sent_articles.json
{
  "sent_guids": ["https://example.com/article/1", "..."],
  "last_checked": "2026-03-31T07:00:00+00:00"
}
```

```python
state = load_state(STATE_FILE)
sent_guids = set(state.get("sent_guids", []))
is_first_run = state.get("last_checked") is None   # last_checked の有無で初回判定

new_entries = [e for e in feed.entries if e.guid not in sent_guids]

# 初回実行時は件数を制限（大量送信でチャンネルが埋まるのを防止）
if is_first_run and len(new_entries) > MAX_FIRST_RUN:
    for e in new_entries[:-MAX_FIRST_RUN]:
        sent_guids.add(e.guid)           # スキップ分も記録して次回送信されないようにする
    new_entries = new_entries[-MAX_FIRST_RUN:]

for entry in new_entries:
    try:
        send_notification(entry)
        sent_guids.add(entry.guid)       # 成功したものだけ記録
    except Exception:
        continue                          # 失敗分は記録しない → 次回自動リトライ

state["sent_guids"] = list(sent_guids)
state["last_checked"] = datetime.now(timezone.utc).isoformat()
save_state(STATE_FILE, state)
```

**ポイント**:
- `sent_guids` を `set` で管理してO(1)検索
- 送信**失敗**した記事は `sent_guids` に追加しないことで次回実行時に自動リトライ
- JSON ファイルは GitHub Actions でコミット・プッシュして永続化（GitHub Cache より確実）

## エラーハンドリング

### 例外種別による分岐処理

**状況**: ML推論で全例外を同じように処理していた
**解決策**: 例外の性質に応じて復旧戦略を分ける

```python
try:
    result = run_inference(image)
except ImportError:
    logger.error("モデルロード不可（復旧不能）")
    return None  # 呼び出し元でFAILED処理
except TimeoutError:
    logger.warning("APIタイムアウト（モックで代替）")
    return mock_result()
except Exception:
    logger.error("予期しないエラー（復旧不能）")
    return None
```

## テストパターン

### テストカバレッジ改善戦略
<!-- added: 2026-02-27 -->

**状況**: テストカバレッジが目標（80%）に届かないファイルが複数ある
**解決策**: 3ステップで効率的にカバレッジを改善する

1. **特定**: カバレッジレポートから80%未満のファイルを一覧化
2. **分析**: 未テスト行を確認し、分岐・エラーパス・エッジケースを特定
3. **追加**: ターゲットを絞ったテストを追加（不要な行までテストしない）

**ポイント**: 100%到達にはエラーハンドリングや条件分岐の全パスを網羅する。特にcatchブロック・early return・デフォルト値のパスが漏れやすい。

### 非nullアサーション排除パターン
<!-- added: 2026-02-27 -->

**状況**: TypeScriptで `result.data!.id` のような非nullアサーション(`!`)が型安全性を損なう
**解決策**: 用途に応じて3つのパターンで置き換える

```tsx
// パターン1: expect用（オプショナルチェーン）
// NG: result.data!.id
expect(result.data?.id).toBe("123");

// パターン2: 変数代入用（ガード + throw）
// NG: const id = result.data!.id;
if (!result.data) throw new Error("データが取得できませんでした");
const id = result.data.id;

// パターン3: 配列メソッド用（nullish coalescing）
// NG: result.data!.map(...)
(result.data ?? []).map((item) => item.name);
```

### ID取得のfallbackパターン
<!-- added: 2026-02-27 -->

**状況**: `data?.id ?? ''` のようなfallbackは、テストでnull/undefinedの場合に空文字列でテストが「成功」してしまい、実際の問題をマスクする
**解決策**: `?? ''` の代わりにガードパターンでテスト失敗を明示的にする

```tsx
// NG: テスト失敗をマスクする
const userId = data?.id ?? '';
expect(userId).toBe("user-123");  // dataがnullでも空文字列でfailするだけで原因が不明

// OK: 原因が明確になる
if (!data) throw new Error("ユーザーデータが取得できませんでした");
expect(data.id).toBe("user-123");
```

## エスカレーションラダー（ルール違反対応）
<!-- added: 2026-04-11, moved from kaggle/CLAUDE.md -->

| レベル | 方式 | 昇格タイミング |
|--------|------|--------------|
| L1 | CLAUDE.mdに記載 | 初回違反 |
| L2 | エージェント(evaluator)が検証 | 同じ違反が3回 |
| L3 | バリデーションスクリプト(validate_*.sh)で自動検証 | L2をすり抜ける |
| L4 | PostToolUseフックで強制ブロック | ビジネスクリティカル（提出事故等） |

**実例:**
- OOF列順ミス → L1(CLAUDE.mdに注意書き) → L3(validate_oof.shで自動検証)
- 提出ファイル分布異常(LB 0.007事故) → L4(validate_submission.shでフック化)

## Kaggleハーネスゲート（品質管理）
<!-- added: 2026-04-11, moved from kaggle/CLAUDE.md -->

### Champion-Challenger昇格ゲート
新モデルがchampionを超える場合のみ本流に昇格:
```bash
uv run python scripts/promote_candidate.py <oof_name>
```
- BA改善 > 0.0003 かつ fold間分散が悪化しない場合のみ昇格
- champion情報は `oof/.champion.json` に保存

### Submission Two-Key Gate
提出前に2つのチェックを通す:
```bash
uv run python scripts/submission_gate.py <submission_file>
```
- バリデーション通過 + champion比較で改善確認

### Score Uncertainty Gate
CV改善がノイズか実力差かを判定:
```bash
uv run python scripts/score_uncertainty.py <oof_name>
```
- bootstrap信頼区間で改善の有意性を検証

### Experiment Registry
```bash
uv run python scripts/register_experiment.py <oof_name> <model_type>
```

### Token/API Budget Governor
```bash
uv run python scripts/budget_governor.py
```