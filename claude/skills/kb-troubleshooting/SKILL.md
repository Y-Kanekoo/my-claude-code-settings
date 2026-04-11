---
name: kb-troubleshooting
description: 技術横断のトラブルシューティング集。遭遇した問題と解決策を蓄積
user-invocable: true
entry_count: 15
last_updated: 2026-04-08
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

---

## 12. OOF列順ミス（Kaggle多クラス分類）

**期待**: LABEL_CLASSES順(High=0, Low=1, Medium=2)のOOF
**実際**: 1位NBのマッピング(Low=0, Medium=1, High=2)でOOF保存 → LB 0.007
**修正**: OOF保存時に列入替(col0↔col2)。validate_oof.shで自動検証

**再発防止**: PostToolUseフックでOOF品質を自動チェック。ターゲットマッピングが異なるスクリプト間でOOFを受け渡す場合は必ず列順を確認

---

## 13. Kaggle API competition_sourcesのパスズレ

**期待**: `/kaggle/input/playground-series-s6e4/train.csv`
**実際**: `/kaggle/input/competitions/playground-series-s6e4/train.csv`（`competitions/`サブディレクトリ）
**修正**: パス自動検出ロジックを全NBに追加

**再発防止**: NBテンプレートにパス自動検出を標準搭載

---

## 14. Codex sandbox内でのMPS GPU無効

**期待**: `codex exec --sandbox workspace-write` でMPS GPU使用可能
**実際**: sandbox環境でMPS available=False
**修正**: DLモデル訓練はCodexではなくClaude側で`uv run python`直接実行

**再発防止**: GPU必要なタスクはCodexにスクリプト生成のみ委譲し、実行はローカルで行う

---

## 15. guard-dangerous-bash.shがgit rm --cachedをブロック

**期待**: `git rm --cached -r external_nb/` でGit追跡から除外（ファイル自体は残る）
**実際**: PreToolUseフックが「rm -r」パターンを検出してブロック
**修正**: git rm --cachedは安全な操作。個別ファイルで対応するか、フックに例外追加

**再発防止**: guard-dangerous-bash.shに `git rm --cached` の例外を追加検討
