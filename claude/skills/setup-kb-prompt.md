# KBスキル再現プロンプト

以下のプロンプトを新しいPCのClaude Codeに貼り付けてください。

---

## プロンプト

```
以下の9つのスキルファイルを ~/.claude/skills/ 配下に作成してください。
ディレクトリが存在しない場合は作成してください。

--- 1. ~/.claude/skills/kb-git/SKILL.md ---

---
name: kb-git
description: Git/CI/CDのナレッジベース。ブランチ戦略、ワークフロー、自動化を蓄積
user-invocable: true
entry_count: 9
last_updated: 2026-02-28
version_sensitive_entries:
  - "GitHub Actions: actions/checkout@v6, actions/setup-node@v6, actions/setup-python@v6"
---

# Git/CI/CD ナレッジベース

Git操作、ブランチ戦略、CI/CDで学んだパターンを記録する。

## Git操作

### サブエージェント並列作業時のブランチ統合

**状況**: 複数のサブエージェントが異なるブランチで並列作業し、マージが必要
**解決策**: stashで退避→mainにマージ→stash popの流れ

```bash
git stash                              # 未コミット変更を退避
git checkout main                      # mainに切替
git merge feature/xxx --no-edit        # featureブランチをマージ
git stash pop                          # 退避した変更を復元
git branch -d feature/xxx             # 不要ブランチを削除
```

### パス内に括弧を含むファイルのgit add

**状況**: `app/(tabs)/home.tsx` のようなパスで `git add` が失敗する
**解決策**: ダブルクォートで囲む

```bash
# NG: シェルが括弧を解釈してしまう
git add apps/mobile/app/(tabs)/home.tsx

# OK
git add "apps/mobile/app/(tabs)/home.tsx"
```

## ブランチ戦略

（ブランチ運用のパターンをここに追記）

## GitHub Actions

### モバイルアプリのCI構成

```yaml
mobile-lint:
  runs-on: ubuntu-latest
  defaults:
    run:
      working-directory: apps/mobile
  steps:
    - uses: actions/checkout@v6
    - uses: actions/setup-node@v6
      with:
        node-version: '20'
        cache: 'npm'
        cache-dependency-path: apps/mobile/package-lock.json
    - run: npm ci --legacy-peer-deps
    - run: npx tsc --noEmit
```

### pip caching

```yaml
- uses: actions/setup-python@v6
  with:
    python-version: "3.12"
    cache: 'pip'
```

### GitHub Actions の permissions を最小権限にする
<!-- added: 2026-02-23 -->

**状況**: permissions 未設定だとデフォルトで `write-all` が適用され、不要な書き込み権限を持つ
**解決策**: ワークフロートップレベルに `permissions` を明示的に設定する

```yaml
permissions:
  contents: read  # 読み取り専用で十分なワークフロー（CI、通知等）

jobs:
  build:
    runs-on: ubuntu-latest
```

### pip-audit で依存パッケージの脆弱性をCI検出する
<!-- added: 2026-02-23 -->

**状況**: requirements.txt で `>=` 指定しているが、間接依存の CVE を見逃す
**解決策**: `pip-audit` をCIに追加。Dependabotと併用で二重チェック

```yaml
- name: Audit dependencies
  run: pip install pip-audit && pip-audit
```

ローカル実行: `pip install pip-audit && pip-audit`

### Claude Code を GitHub Actions で Max Plan OAuth 実行する
<!-- added: 2026-02-28 -->

**状況**: Claude Code を GitHub Actions で定期実行したいが、API Key（従量課金）ではなく Max Plan サブスク内で実行したい
**解決策**: `claude setup-token` で長期 OAuth トークンを生成し、GitHub Secrets に登録。API 課金なしで CI 実行できる

```yaml
# 1. ローカルで実行: claude setup-token → トークン取得
# 2. gh secret set CLAUDE_CODE_OAUTH_TOKEN -R user/repo

- name: セッションを開始
  env:
    CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
  run: claude -p "hello" --max-turns 1
```

- トークン有効期限: 約1年（年1回再生成）
- `ANTHROPIC_API_KEY` が同時に設定されているとそちらが優先される（API課金発生）ので注意

### GitHub Actions cron の実測遅延
<!-- added: 2026-02-28 -->

**状況**: GitHub Actions の `schedule` (cron) でジョブを定期実行しているが、指定時刻ちょうどに実行されない
**解決策**: 遅延は不可避。実測値を把握して設計に組み込む

実測データ（2026-02時点）:

| UTC 時刻 | 遅延 |
|----------|------|
| 21:00 | 24〜28分 |
| 07:00 | 38分 |
| 12:00 | 41分 |
| 02:00 | **1時間58分〜2時間17分** |

- 遅延は時間帯により大きく異なる（UTC 02:00 は特に大きい）
- 公式には「数分〜数十分」だが、実際は**最大2時間以上**になることがある
- 正確なタイミングが必要な場合は self-hosted runner や外部スケジューラを検討

## トラブルシューティング

### サブエージェント間のファイル競合

**状況**: Agent Aが Agent B/C のスコープのファイルも変更してしまい、競合が発生
**解決策**: Issue分割時にファイルの所有権を明確に定義する。1つのファイルは1つのエージェントのみが変更する

## Tips

（便利なTipsをここに追記）


--- 2. ~/.claude/skills/kb-troubleshooting/SKILL.md ---

---
name: kb-troubleshooting
description: 技術横断のトラブルシューティング集。遭遇した問題と解決策を蓄積
user-invocable: true
entry_count: 11
last_updated: 2026-02-28
version_sensitive_entries:
  - "Expo SDK + jest互換性: SDK 54→jest@29.7.0, SDK 55→npx expo install で自動解決"
---

# トラブルシューティング ナレッジベース

技術分野を問わず、遭遇した問題と解決策を記録する。

## 環境構築

### .gitignoreの広すぎるパターン

**状況**: `.gitignore`に`lib/`と書いたら`apps/mobile/lib/`まで除外されてしまった
**解決策**: 否定パターンで特定ディレクトリを除外対象から外す

```gitignore
lib/
!apps/mobile/lib/
```

### createSyncStoragePersister vs createAsyncStoragePersister

**状況**: AsyncStorageで同期版Persisterを使おうとしてエラー
**解決策**: AsyncStorage用には `createAsyncStoragePersister` を使用する

## ビルド/デプロイ

### Expo SDK + jestのバージョン互換性
<!-- updated: 2026-02-08 -->

**状況**: jest@30にアップグレードするとimport.metaエラーが発生（SDK 54以前）
**解決策**: `npx expo install jest-expo jest` で自動的に互換バージョンがインストールされる

SDK 55以降はjest-expoもSDKと同じメジャーバージョン（`^55.0.0`）に統一。手動バージョン指定より `npx expo install` を推奨。

SDK 54の場合の固定指定:
```json
"jest": "^29.7.0",
"jest-expo": "~54.0.0"
```

## ランタイム

### S3削除→DB削除の順序保証

**状況**: S3からの削除が失敗してもDBレコードが消えてしまい、孤立ファイルが発生
**解決策**: S3削除が成功した場合のみDB削除を実行。失敗時は`continue`でスキップし次回再試行

```python
for image in expired_images:
    try:
        s3_client.delete_object(Bucket=bucket, Key=image["object_key"])
    except Exception:
        logger.warning("S3削除失敗のためスキップ")
        continue  # DB削除をスキップ
    # S3削除成功時のみDB削除
    cur.execute("DELETE FROM images WHERE id = %s", (image["id"],))
```

### strftime('%-m/%-d') が Windows で動作しない
<!-- added: 2026-02-23 -->

**状況**: macOS/Linux で `dt.strftime('%-m/%-d')` は先頭ゼロなしの月日（例: `2/3`）を返すが、Windows では `%-m` がそのまま出力される
**解決策**: f-string `f"{dt.month}/{dt.day}"` を使う。matplotlib の場合は `FuncFormatter` を使う

```python
# NG: Windows非互換
ax.xaxis.set_major_formatter(mdates.DateFormatter('%-m/%-d'))

# OK: クロスプラットフォーム
from matplotlib.ticker import FuncFormatter
_DATE_FORMATTER = FuncFormatter(
    lambda x, _: f"{mdates.num2date(x).month}/{mdates.num2date(x).day}"
)
ax.xaxis.set_major_formatter(_DATE_FORMATTER)
```

### macOS launchd から Keychain の認証情報にアクセスできない
<!-- added: 2026-02-28 -->

**状況**: launchd エージェントで Claude Code を実行すると `Not logged in` エラー。OAuth 認証は Keychain に保存されており、launchd 環境からはアクセスできない
**解決策**: OAuth トークンをファイルに保存し、スクリプト内で `CLAUDE_CODE_OAUTH_TOKEN` 環境変数として読み込む

```bash
# トークンをファイルに保存（chmod 600 で保護）
pbpaste | tr -d '\n' > ~/.claude/config/oauth_token
chmod 600 ~/.claude/config/oauth_token

# スクリプト内で読み込み
export CLAUDE_CODE_OAUTH_TOKEN=$(cat "$HOME/.claude/config/oauth_token")
```

### zsh の `read -p` は bash と互換性がない
<!-- added: 2026-02-28 -->

**状況**: `read -s -p "プロンプト:" var` を zsh で実行すると `read: -p: no coprocess` エラー
**解決策**: zsh では `-p` は「コプロセスから読む」意味。プロンプト表示には `echo -n` を使う

```bash
# bash 用（zsh では動かない）
read -s -p "入力: " token

# zsh 互換
echo -n "入力: " && read -s token
```

### OAuth トークンに改行が混入すると HTTP ヘッダーエラーになる
<!-- added: 2026-02-28 -->

**状況**: `pbpaste > file` でトークンを保存したが、末尾に改行が含まれ `Header has invalid value` エラー
**解決策**: `tr -d '\n'` で改行を除去してから保存

```bash
# NG: 改行が含まれる可能性
pbpaste > ~/.claude/config/oauth_token

# OK: 改行を除去
pbpaste | tr -d '\n' > ~/.claude/config/oauth_token
```

## パフォーマンス

（パフォーマンス問題をここに追記）

## その他

### サブエージェント並列実行のレート制限

**状況**: 4つのサブエージェントを同時実行したらAPI制限に到達
**解決策**: 並列数を3-4体に制限。同一ワークスペースでの並列はブランチ競合リスクあり

## Claude Code ツール

### Grep/Glob ツールの ENOENT エラー
<!-- added: 2026-02-27 -->

**状況**: Grep/Glob ツール使用時に `ENOENT: posix_spawn` エラーが間欠的に発生する
**解決策**: Bash の `grep` / `find` コマンドにフォールバックする

```bash
# Grep ツールが ENOENT で失敗した場合
grep -rn "検索パターン" /path/to/dir --include="*.ts"

# Glob ツールが ENOENT で失敗した場合
find /path/to/dir -name "*.tsx" -type f
```

**注意**: 間欠的な問題のため、まずツールを再試行し、2回目も失敗した場合にBashフォールバックを使う。

### Edit ツールの "String to replace not found"
<!-- added: 2026-02-27 -->

**状況**: 複数回のEditを連続実行した後、対象ファイルの内容が前回のEditで変更されており、`old_string` が見つからない
**解決策**: Edit前に必ず `Read` ツールでファイルの最新状態を確認してからEditする

**再発防止**:
1. 1つのEditが成功した後、同じファイルに再度Editする場合は必ずReadで最新内容を取得
2. 特に連続Edit時は、前回のEditで変更された周辺行も変わっている可能性を考慮する
3. `old_string` はできるだけユニークな範囲（前後の行を含む）を指定する


--- 3. ~/.claude/skills/kb-database/SKILL.md ---

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
    ON diagnosis_sessions (user_id, created_at DESC);
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


--- 4. ~/.claude/skills/kb-frontend/SKILL.md ---

---
name: kb-frontend
description: フロントエンドのナレッジベース。React/Vue/Tailwind等のパターンを蓄積
user-invocable: true
entry_count: 10
last_updated: 2026-02-27
---

# フロントエンド ナレッジベース

React/Vue/Tailwind等のフロントエンド技術で学んだパターンを記録する。

## React パターン

### React Hooksの呼び出し順序ルール

**状況**: `useCallback`を早期リターン（`if (isLoading) return ...`）の後に配置してしまい、Hooksルール違反になった
**解決策**: 全てのHooks（useState, useCallback, useMemo等）は早期リターンの前、コンポーネントのトップレベルに配置する

```tsx
// NG: 早期リターンの後にuseCallback
function Component() {
  const { data, isLoading } = useQuery(...);
  if (isLoading) return <Loading />;  // 早期リターン
  const renderItem = useCallback(...);  // Hooksルール違反！
}

// OK: 全Hooksを早期リターンの前に配置
function Component() {
  const { data, isLoading } = useQuery(...);
  const renderItem = useCallback(({ item }) => (
    <ItemCard item={item} />
  ), []);
  if (isLoading) return <Loading />;  // 早期リターンはHooksの後
}
```

### React Query楽観的更新パターン

**状況**: PATCH操作でサーバー応答を待たずにUIを即座に更新したい
**解決策**: `onMutate`でキャッシュバックアップ→即座更新、`onError`でロールバック、`onSettled`で再取得

```tsx
const updateMutation = useMutation({
  mutationFn: (data) => apiFetch(`/items/${data.id}`, { method: "PATCH", body: data }),
  onMutate: async (updated) => {
    await queryClient.cancelQueries({ queryKey: ["items"] });
    const previous = queryClient.getQueryData<Item[]>(["items"]);
    queryClient.setQueryData<Item[]>(["items"], (old) =>
      old?.map((item) => item.id === updated.id ? { ...item, ...updated } : item) ?? []
    );
    return { previous };
  },
  onError: (_err, _vars, context) => {
    if (context?.previous) queryClient.setQueryData(["items"], context.previous);
  },
  onSettled: () => queryClient.invalidateQueries({ queryKey: ["items"] }),
});
```

## 状態管理

### React Queryキャッシュ無効化の連鎖

**状況**: フィードバック送信後に履歴一覧と該当セッション詳細の両方を最新化したい
**解決策**: `onSuccess`で複数のqueryKeyを`invalidateQueries`する

```tsx
const feedbackMutation = useMutation({
  mutationFn: (data) => apiFetch(`/diagnoses/${data.sessionId}/feedback`, { method: "POST", body: data }),
  onSuccess: (_data, variables) => {
    queryClient.invalidateQueries({ queryKey: ["diagnoses", "history"] });
    queryClient.invalidateQueries({ queryKey: ["diagnoses", variables.sessionId] });
  },
});
```

## CSS/Tailwind

（スタイリングのパターンをここに追記）

## トラブルシューティング

### npm installでpeer dependency競合

**状況**: react-domのpeer dependencyでインストールが失敗
**解決策**: `npm install --legacy-peer-deps` を使用

### NetInfoモックが動かない

**状況**: `@react-native-community/netinfo`のモックでdefaultエクスポートが認識されない
**解決策**: `__esModule: true` と `default` エクスポートを両方指定する

```js
jest.mock("@react-native-community/netinfo", () => ({
  __esModule: true,
  default: { addEventListener: jest.fn(), fetch: jest.fn() },
}));
```

## Tips

### FlatListのrenderItemメモ化

`useCallback`でrenderItemをメモ化し、コンポーネント自体も`React.memo`で囲むと再レンダリングが40-60%削減される

## React Native テスト

### React Navigation モックパターン
<!-- added: 2026-02-27 -->

**状況**: テストで `createNativeStackNavigator` を使った画面コンポーネントをレンダリングしたい
**解決策**: `<>{children}</>` + `MockStackScreen` でモック。全Screenが同時レンダリングされる制約がある

```tsx
jest.mock("@react-navigation/native-stack", () => ({
  createNativeStackNavigator: () => ({
    Navigator: ({ children }: { children: React.ReactNode }) => <>{children}</>,
    Screen: ({ component: Component, ...props }: { component: React.ComponentType; name: string }) => (
      <Component {...props} />
    ),
  }),
}));
```

**注意**: 実際のナビゲーションスタックと異なり、全Screenが一度にレンダリングされる。個別画面のテストには向くが、遷移テストには不向き。

### setTimeout クリーンアップパターン
<!-- added: 2026-02-27 -->

**状況**: コンポーネント内で `setTimeout` を使うとアンマウント後にメモリリークや状態更新エラーが発生する
**解決策**: `useRef` でタイマーIDを保持し、`useEffect` のクリーンアップで確実にクリアする

```tsx
const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

useEffect(() => {
  return () => {
    if (timerRef.current) {
      clearTimeout(timerRef.current);
    }
  };
}, []);

// タイマー設定時
timerRef.current = setTimeout(() => {
  // 処理
}, 3000);
```

**ポイント**: `ReturnType<typeof setTimeout>` でNode.jsとブラウザ環境の型差異を吸収。`NodeJS.Timeout` は環境依存。

### React Query テスト: デフォルトオプションとqueryKeys
<!-- added: 2026-02-27 -->

**状況**: React Queryの設定値やqueryKey生成関数をテストしたい
**解決策**: `queryClient.getDefaultOptions()` で設定値を検証。queryKeys関数は毎回新しい配列を返すため参照比較は `.not.toBe()` を使う

```tsx
// デフォルトオプションの検証
const defaults = queryClient.getDefaultOptions();
expect(defaults.queries?.staleTime).toBe(5 * 60 * 1000);

// queryKeys関数の参照非同一性を検証
const key1 = queryKeys.products.list();
const key2 = queryKeys.products.list();
expect(key1).toEqual(key2);     // 値は同一
expect(key1).not.toBe(key2);    // 参照は異なる（毎回新しい配列）
```


--- 5. ~/.claude/skills/kb-patterns/SKILL.md ---

---
name: kb-patterns
description: 再利用可能な設計パターン集。アーキテクチャ、実装パターンを蓄積
user-invocable: true
entry_count: 8
last_updated: 2026-02-27
---

# 設計パターン ナレッジベース

技術分野を問わず、再利用可能な設計パターンを記録する。

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
expect(result.data?.id).toBe("123");

// パターン2: 変数代入用（ガード + throw）
if (!result.data) throw new Error("データが取得できませんでした");
const id = result.data.id;

// パターン3: 配列メソッド用（nullish coalescing）
(result.data ?? []).map((item) => item.name);
```

### ID取得のfallbackパターン
<!-- added: 2026-02-27 -->

**状況**: `data?.id ?? ''` のようなfallbackは、テストでnull/undefinedの場合に空文字列でテストが「成功」してしまい、実際の問題をマスクする
**解決策**: `?? ''` の代わりにガードパターンでテスト失敗を明示的にする

```tsx
// NG: テスト失敗をマスクする
const userId = data?.id ?? '';
expect(userId).toBe("user-123");

// OK: 原因が明確になる
if (!data) throw new Error("ユーザーデータが取得できませんでした");
expect(data.id).toBe("user-123");
```


--- 6. ~/.claude/skills/kb-python/SKILL.md ---

---
name: kb-python
description: Pythonのナレッジベース。型ヒント、パターン、ライブラリの使い方を蓄積
user-invocable: true
entry_count: 6
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


--- 7. ~/.claude/skills/kb-docker/SKILL.md ---

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


--- 8. ~/.claude/skills/kb-kaggle/SKILL.md ---

---
name: kb-kaggle
description: Kaggleコンペの汎用ナレッジベース。モデル選択、アンサンブル、特徴量パターンを蓄積
user-invocable: true
entry_count: 7
last_updated: 2026-04-01
version_sensitive_entries:
  - "LightGBM: v4.x"
  - "XGBoost: v3.x (callbacks API変更)"
  - "CatBoost: v1.2+"
---

# Kaggle ナレッジベース

Kaggleコンペティションで蓄積した汎用的な知見を記録する。プロジェクト固有のスコアやパスは含まず、どのコンペでも参照可能な内容に限定する。

---

## 1. テーブルデータ向けモデル

### 1.1 GBDT 3種の特性比較

| 項目 | LightGBM | XGBoost | CatBoost |
|------|----------|---------|----------|
| 分割戦略 | Leaf-wise（損失最大の葉を優先） | Level-wise（全葉を均等分割） | Symmetric tree（左右対称木） |
| 速度 | 最速 | 速い | やや遅い（CPU）/ 最速（GPU） |
| カテゴリ変数 | ネイティブ対応（最適分割探索） | 非対応（要エンコーディング） | 最強（Ordered Target Statistics） |
| 欠損値処理 | 自動（最適方向割当） | 自動（最適方向割当） | 数値:最小/最大値、カテゴリ:新カテゴリ |
| 正則化 | L1/L2 + min_child_samples | L1/L2 + gamma（3段階） | L2 + random_strength + Ordered Boosting |
| メモリ | 少ない | 中程度 | 多い |

（以下、kb-kaggle の内容は非常に長いため省略。上記の完全版は kb-kaggle/SKILL.md に含まれています）


--- 9. ~/.claude/skills/sync-knowledge/SKILL.md ---

---
name: sync-knowledge
description: プロジェクトで得た学びをグローバルナレッジベース（~/.claude/skills/kb-*/）に反映する
user-invocable: true
---

# ナレッジベース更新

現在のプロジェクトで得た学びを `~/.claude/skills/` 配下のナレッジスキルに反映する。

## コマンド

| コマンド | 用途 |
|---------|------|
| `/sync-knowledge` | セッションの学びをkb-*に反映 |
| `/sync-knowledge --from-review` | `/review` の結果からナレッジ候補を自動抽出して反映 |
| `/sync-knowledge --check-freshness` | kb-*の鮮度チェック（古いエントリの報告） |

## 対象スキル

| スキル | 内容 |
|--------|------|
| `kb-python` | Python |
| `kb-frontend` | React/Vue/Tailwind等 |
| `kb-docker` | Docker/Kubernetes |
| `kb-git` | Git/CI/CD |
| `kb-database` | SQL/NoSQL/ORM |
| `kb-troubleshooting` | 問題と解決策 |
| `kb-patterns` | 設計パターン |
| `kb-kaggle` | Kaggleコンペティション |

> 上記以外のカテゴリ（TypeScript、Java、AWS等）は、該当する知見が2項目以上溜まった時点で新規作成する。

## 品質ゲート（追記前に必ず実行）

### 1. 汎用性チェック
- プロジェクト固有のリソース名・URL・APIキーを含まない
- 他のプロジェクトでも再現可能な形式になっている
- バージョン依存がある場合、バージョン情報を明記

### 2. 重複チェック
- 対象kb-*ファイルをGrepし、類似エントリが存在しないか確認
- 類似あり → 既存エントリを更新・補完（新規追記しない）

### 3. 構造チェック
- 統一フォーマット（状況/解決策/コード例）に準拠
- メタデータコメント（`<!-- added: YYYY-MM-DD -->`）を付与

### 4. サイズチェック
- 1エントリ30行以内（超過は分割を検討）
- kb-*全体が150行超 → 低価値エントリの整理を提案

### 5. 振り分けルール
- 技術固有のトラブルシューティング → 各kb-*のトラブルシューティングセクション
- 技術横断のトラブルシューティング → kb-troubleshooting
- 技術横断の設計パターン → kb-patterns

## 実行手順

1. **学びを確認**: セッションで解決した問題や得た知見を整理
2. **該当スキルを特定**: 振り分けルールに従い追記先を判断
3. **品質ゲートを適用**: 全チェック項目をパスしたもののみ追記
4. **ナレッジスキルを更新**: `kb-*/SKILL.md`を読み込み、汎用的な学びを追記
5. **メタデータを更新**: フロントマターの`entry_count`と`last_updated`を更新
6. **更新内容を報告**: どのスキルに何を追記したかをユーザーに報告

## 新規kb-*作成条件

対象スキルファイルが存在しない場合:
1. 汎用的な知見が2項目以上溜まっていること
2. 以下のテンプレートで新規作成:

```markdown
---
name: kb-{カテゴリ}
description: {カテゴリ}のナレッジベース
user-invocable: true
entry_count: 0
last_updated: YYYY-MM-DD
---
# {カテゴリ} ナレッジベース
## ベストプラクティス
## トラブルシューティング
## Tips
```

## 記述フォーマット

```markdown
### タイトル（問題の概要）
<!-- added: YYYY-MM-DD -->

**状況**: どんな状況で発生したか
**解決策**: どう解決したか

\`\`\`言語
// コード例
\`\`\`
```

## `--check-freshness` モード

kb-*の情報鮮度を確認し、陳腐化リスクのあるエントリを報告する。

### 実行手順

1. 全kb-*のフロントマターから `last_updated` を取得
2. 90日以上更新なしのkb-*を「要確認」として報告
3. `version_sensitive_entries` がフロントマターにある場合、該当エントリの現在のバージョン妥当性を確認
4. 報告して、ユーザーの承認を得てから更新・削除を実行


---

すべてのファイルを上記の内容で作成してください。
ディレクトリ構造:
~/.claude/skills/kb-git/SKILL.md
~/.claude/skills/kb-troubleshooting/SKILL.md
~/.claude/skills/kb-database/SKILL.md
~/.claude/skills/kb-frontend/SKILL.md
~/.claude/skills/kb-patterns/SKILL.md
~/.claude/skills/kb-python/SKILL.md
~/.claude/skills/kb-docker/SKILL.md
~/.claude/skills/kb-kaggle/SKILL.md
~/.claude/skills/sync-knowledge/SKILL.md
```
