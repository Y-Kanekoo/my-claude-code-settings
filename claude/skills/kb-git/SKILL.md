---
name: kb-git
description: Git/CI/CDのナレッジベース。ブランチ戦略、ワークフロー、自動化を蓄積
user-invocable: true
entry_count: 11
last_updated: 2026-04-11
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

### GitHub Actions でファイルを自動コミット・プッシュする
<!-- added: 2026-03-31 -->

**状況**: GitHub Actions のジョブ内で生成・更新されたファイル（状態ファイル等）をリポジトリにコミットしたい
**解決策**: `permissions: contents: write` + `concurrency` + 空コミット防止の3点セット

```yaml
concurrency:
  group: rss-check          # 同一グループの実行を直列化
  cancel-in-progress: false # 実行中を止めず、次をキュー待ち

permissions:
  contents: write           # GITHUB_TOKEN にプッシュ権限を付与

# ジョブのステップ
- name: 状態ファイルをコミット
  run: |
    git config user.name "github-actions[bot]"
    git config user.email "github-actions[bot]@users.noreply.github.com"
    git add data/state.json
    git diff --cached --quiet || git commit -m "[chore] 状態を更新"
    git push
```

- `cancel-in-progress: false` にすることで push 競合を防止（true にすると前回のコミット前に次が始まる）
- `git diff --cached --quiet ||` で変更がない場合は空コミットをスキップ
- `github-actions[bot]` 名義にするとコミット履歴で人間のコミットと区別しやすい

## トラブルシューティング

### サブエージェント間のファイル競合

**状況**: Agent Aが Agent B/C のスコープのファイルも変更してしまい、競合が発生
**解決策**: Issue分割時にファイルの所有権を明確に定義する。1つのファイルは1つのエージェントのみが変更する

## 個人Kaggle向けGit運用
<!-- added: 2026-04-11, moved from kaggle/CLAUDE.md -->

### 基本ルール
- **trunk 1本**（master直push）。feature branch/PRは不要
- 危険作業（大規模リファクタ、10ファイル超の変更）だけ短命ブランチ
- コミット条件 = **再現可能な節目**（ベースライン完成/CV改善/submit候補確定/修正完了）
- push前に `validate_oof.sh` + `validate_submission.sh` を通す

### コミットメッセージ
```
[type] 変更内容（任意で結果）
例: [feat] add pairwise TE stacker (CV 0.9778, LB 0.9772)
```

### タグ
- LB/CV節目: `lb-0.97832`, `cv-0.9798`
- 締切前freeze: `deadline-freeze-2026-04-28`
- 最終提出: `final-submit`

### Issue運用
- **使うラベル**: `experiment`, `bug`, `infra`, `submission`, `won't-do`
- 5分で終わるTODOはissue化しない
- 実験計画は `experiment` issueで管理（仮説/変更/期待効果/結果/次の打ち手）
- Claude/Codexに「Issue #12 を実装して」と振れる形にする

### PR運用
- **直push OK**: typo修正、コメント整理、軽いcleanup
- **PR作る**: 特徴量追加、CV戦略変更、提出影響変更、30分以上の作業、AIレビュー対象
- PRは承認フローではなく「差分可視化 + AIレビューの器」
- mergeは基本 **Squash and merge**（履歴を実験単位で残す）
- `--worktree` + branchで実験を分離し、PRでまとめる

### GitHub Actions
- pytest + lint の軽量CIのみ
- 重い学習やKaggle APIは回さない

### Gitに入れるもの/入れないもの
| 入れる | 入れない |
|--------|---------|
| コード(src/, scripts/) | OOF/pred/submission (oof/, submissions/) |
| 設定(config.py, CLAUDE.md) | モデル重み(*.pth, *.pkl) |
| テスト(tests/) | ログ(logs/) |
| 実験メモ(experiment_results*.md) | 外部NB生成物(external_nb/**/*.csv) |

## Tips

（便利なTipsをここに追記）
