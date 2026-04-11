---
name: review
description: プロジェクトのコード品質・設計・テスト・運用を分析し、改善点を優先度付きで報告する
user-invocable: true
---

# プロジェクトレビュースキル

プロジェクトを分析し、改善点を優先度付きで報告する。ソースコードは変更しない。レポートは日本語。

## コマンド

`/review [オプション]`

| コマンド | 用途 | 出力先 |
|---------|------|--------|
| `/review` | フルレビュー | `docs/review-report.md` |
| `/review --quick` | 軽量スキャン（Grepのみ、Read最大15件） | コンソール |
| `/review --staged` | コミット前チェック（ステージング済みのみ） | コンソール |
| `/review --recent` | 直近変更確認（未コミット+直近5コミット） | コンソール |
| `/review --diff` | 前回レポートとの差分 | `docs/review-report.md` |
| `/review --scope <パス>` | 指定パス配下のみ分析 | モードに依存 |
| `/review --focus <領域>` | 特定領域のみ | モードに依存 |

`--focus` の領域: `code` / `docs` / `test` / `ops` / `security` / `perf`

組み合わせ例: `/review --quick --focus security`, `/review --scope src/api --focus code`

**組み合わせ優先ルール**:
- 対象範囲: `--staged` > `--recent` > `--scope` > `--diff` > 全体（左が優先）
- 出力先: `--quick`/`--staged`/`--recent` → コンソール。それ以外 → ファイル
- 深さ: `--quick` → Grep+Read15件。フル → Grep+Read30件+構造分析

## 除外対象

`node_modules/`, `dist/`, `build/`, `.next/`, `vendor/`, `__pycache__/`, `venv/`, `.venv/`, `target/`, `.git/`, `*.lock`, `*.min.*`, 生成ファイル全般。以下のコマンド例はすべてこの除外を適用する。

---

## Phase 0: コンテキスト収集

### 0-1. スタック検出（並列Glob → Read）

`package.json`, `tsconfig.json`, `pyproject.toml`, `requirements.txt`, `go.mod`, `Cargo.toml`, `pom.xml`, `build.gradle*`, `Gemfile`, `composer.json`, `*.sln`, `Dockerfile`, `docker-compose*.yml` を並列Globし、検出したファイルをReadする。

### 0-2. 規模・構成（並列Bash、集計目的のためBash使用）

```bash
find . -type f -not -path './.git/*' -not -path './node_modules/*' -not -path './.venv/*' -not -path './vendor/*' -not -path './target/*' -not -path './dist/*' -not -path './build/*' | wc -l
find . -maxdepth 2 -type d -not -path './.git/*' -not -path './node_modules/*' -not -path './.venv/*' -not -path './vendor/*' | sort | head -60
```

### 0-3. Git・規約・既存資産（並列）

- `git status -s`, `git log --oneline -5`, `git diff --name-only HEAD~5..HEAD`
- `Read("CLAUDE.md")` → 禁止事項・規約を抽出。違反は自動的に影響度=高
- テストファイル、CI/CD設定、`docs/review-report.md`（前回レポート）の有無をGlob

### 0-4. linter実行（0-1完了後、該当スタックのみ）

導入済みの品質ツールを実行し、結果を取得する。後続のGrepではlinter検出済み範囲をスキップする。
```bash
npx eslint . --format json --quiet 2>/dev/null | head -200
ruff check . --output-format json 2>/dev/null | head -200
npm audit --json 2>/dev/null | head -100
pip audit --format json 2>/dev/null | head -100
```
ツール不在/失敗時はスキップし、手動分析にフォールバック。

### 0-5. プロジェクト段階の判定

| 段階 | 基準 |
|------|------|
| プロトタイプ | テストなし、README最小限 |
| アルファ | テスト少量（テスト/ソース比 〜20%）、基本構成あり |
| ベータ | テストあり（20%〜）、CI/CD設定あり、バージョン0.x |
| プレリリース | テスト充実（60%〜）、CI/CD整備済み、バージョン1.x近傍 |

### 0-6. 構成決定・報告

**モノレポ検出**: `workspaces`, `lerna.json`, `pnpm-workspace.yaml`, 複数`package.json` → ユーザーに対象確認。

**エージェント構成**:

| モード | 規模 | 構成 |
|--------|------|------|
| フル | 〜50ファイル | 直列 |
| フル | 50〜500 | 3エージェント並列 |
| フル | 500〜2000 | 3エージェント並列+サンプリング |
| フル | 2000+ | 3エージェント並列+ディレクトリ単位分割 |
| 軽量 | 任意 | 直列（サブエージェントなし） |

**フルモード**: 結果を報告し、ユーザーの確認を得てからPhase 1へ。
**軽量モード**: 結果を報告し、即座にPhase 1へ。

---

## Phase 1〜3: 分析

### 対象ファイルの決定

| モード | 対象 |
|--------|------|
| フル / `--quick` | 全体（`--scope`指定時はそのパス配下） |
| `--staged` | `git diff --cached --name-only` |
| `--recent` | `git diff --name-only HEAD` + `git diff --name-only HEAD~5..HEAD` |
| `--diff` | `git diff --name-only <前回コミット>..HEAD` |

### サブエージェントへの共通コンテキスト

プロジェクトルート、技術スタック、規模、段階、CLAUDE.md規約、linter結果、対象ファイル一覧、前回指摘。
制約: 「ソースコード変更不可」「日本語報告」「指摘は最大15件。超過時は重大度順に絞り残件数を記載」

### `--focus` と Agent の対応

| `--focus` | 実行するAgent |
|-----------|-------------|
| `code` / `security` / `perf` | Agent 2 |
| `docs` | Agent 1 |
| `test` / `ops` | Agent 3 |
| 指定なし | 全Agent |

---

### Agent 1: 構成・ドキュメントレビュー

**subagent_type: Explore** | フルモードのみ実行

ドキュメントの過不足を評価する（作成は行わない）。README、環境構築手順、仕様、設計、API仕様の有無と正確性を確認。コードとドキュメントの乖離を検出。

出力: 指摘ID `D-001`〜。フィールド: ID, 重大度, カテゴリ, 対象, 問題, 対応, 工数, 根拠。

---

### Agent 2: コード品質レビュー

**subagent_type: Explore** | 全モードで実行

#### ステップ1: パターンスキャン（Grep、linter検出済み項目はスキップ）

共通:
```
Grep("TODO|FIXME|HACK|XXX|BUG")
Grep("debugger\\b")
Grep("(password|secret|api_?key)\\s*[:=]\\s*[\"'][^\"']+[\"']", glob: "*.{ts,js,py,go,java,rb,yml,yaml,json}")
Grep("(log|console|logger|print).*?(password|token|secret|credential)", glob: "*.{ts,js,py,go,java}")
```

スタック別（検出したスタックに応じて選択）:
```
TypeScript:  Grep(": any\\b|as any\\b|@ts-ignore|@ts-nocheck", type: "ts")
Python:      Grep("except:\\s*$|\\beval\\s*\\(|\\bexec\\s*\\(", type: "py")
Go:          Grep("_\\s*=\\s*\\w+\\(", type: "go")
Java:        Grep("catch\\s*\\(\\s*Exception\\s", type: "java")
React:       Grep("useEffect\\(.*\\[\\]", type: "tsx")
SQL/ORM:     Grep("\\.raw\\s*\\(|\\.rawQuery|\\.execute\\s*\\(", glob: "*.{ts,js,py,go,java}")
```

各Grepのヒットは上位20件まで確認する。

#### ステップ2: 重要ファイルの詳細調査（Read）

優先順: 外部境界（API, 認証） > ビジネスロジック中核 > データアクセス層 > ステップ1ヒット > 巨大ファイル。
上限: 軽量15件、フル30件（500+ファイル時は各300行まで）。

#### ステップ3: 構造分析（フルモードのみ）

巨大ファイル検出（Bash `wc -l | sort -rn | head -20`）、構成評価、モジュール粒度。

#### レビュー観点

共通: セキュリティ、エラーハンドリング一貫性、入力バリデーション、並行性・状態管理、パフォーマンス（メモリリーク, 不要ループ, キャッシュ欠如）、障害耐性（タイムアウト設定, リトライ戦略, サーキットブレーカー）、エッジケース、CLAUDE.md規約違反。

スタック別:

| スタック | 追加観点 |
|----------|---------|
| TypeScript | any, 型不足, strict, 型アサーション乱用 |
| React/Vue | 再レンダリング, hooks規則, key, a11y |
| Python | 型ヒント, async一貫性 |
| Go | goroutineリーク, context, error wrapping |
| Rust | unwrap()混入, unsafe, ライフタイム |
| Java/Kotlin | Null安全, スレッドセーフ, DI |
| API | 認証/認可, レスポンス一貫性, 後方互換性 |
| DB | N+1, トランザクション, マイグレーション |
| Docker/K8s | USER root, リソースリミット, ヘルスチェック |

出力: 指摘ID `C-001`〜。フィールド: ID, 重大度, カテゴリ, ファイル:行, 問題, 対応, 修正案(diff), 工数, 影響範囲, 根拠。技術的負債一覧も付記。

---

### Agent 3: テスト・設定・運用レビュー

**subagent_type: Explore**（Phase 0でlinter/audit結果は取得済み）
**フルモード**: 全項目実行 | **軽量モード**: テスト有無+設定管理のみ（運用・CI/CDはスキップ）

#### テスト品質

- テストゼロ → 最優先テスト箇所Top5〜10を提示（金銭処理 > 認証 > バリデーション > 外部API > 複雑分岐）
- テストあり → ピラミッド構造、決定性、テスタビリティ（DI, 密結合）、アサーション有無を評価
- テストとソースの対応マッピング: テストが存在しない重要ソースファイルを特定

#### 設定管理

`.env.example`有無、シークレットハードコード、設定バリデーション（fail-fast）、デフォルト値安全性。

#### 運用準備（段階別、Webアプリ/APIの場合）

- アルファ: 構造化ログ（`winston`/`pino`/`structlog`/`zap`等の導入確認）、基本エラーハンドリング
- ベータ: ヘルスチェック、シークレット管理、CI/CD
- プレリリース: Observability（ログ/メトリクス/トレース）、アラート、バックアップ、Graceful Degradation

#### CI/CD・依存

テスト自動実行、lint/format、ビルド検証、セキュリティスキャン、依存脆弱性（Phase 0結果を流用）、非推奨パッケージ。

出力: 指摘ID `T-001`〜。フィールド: ID, 重大度, カテゴリ(テスト/設定/運用/依存/CI-CD), 対象, 問題, 対応, 工数, 根拠。テスト優先実装リストも付記。

---

## Phase 4: 統合・出力

### 4-1. クロスリファレンス（フルモードのみ）

ドキュメント↔コード↔テストの整合性、重複統合、指摘間の依存関係、前回レポートとの照合。
セキュリティ横断チェック: Agent 2のコードレベル + Agent 3の設定レベル + Phase 0の検出結果を統合。

### 4-2. 重大度と4象限分類

| 重大度 | 定義 | 例 |
|--------|------|-----|
| Critical | 本番障害・データ損失・セキュリティ侵害 | SQLインジェクション, 秘密鍵ハードコード, 認証バイパス |
| High | 機能不全・重大劣化 | 例外握りつぶし, 未検証入力DB投入, タイムアウト未設定 |
| Medium | 品質・保守性に影響するが動作する | 重複ロジック, N+1, any使用, テスト不足 |
| Low | 改善が望ましいが緊急性なし | 未使用import, 命名不統一, 非推奨API, TODO残留 |

自動昇格: CLAUDE.md禁止事項違反 → 最低High。

| 工数 | 基準 |
|------|------|
| small | 単一ファイル、10行以内 |
| medium | 2〜5ファイル、設計判断必要 |
| large | 6ファイル以上、アーキテクチャ変更 |

**4象限分類**:
- **[1] 今すぐやる**: Critical/High × small → Now
- **[2] 計画的に対応**: Critical/High × medium/large → Plan（大工数Criticalは暫定対処案も提示）
- **[3] 手が空いたら**: Medium/Low × small/medium → Soon
- **[4] 余裕があれば**: Medium/Low × large → Later

### 4-3. 出力

**フルモード** → `docs/review-report.md`（YAMLフロントマター付き）:

```yaml
---
schema_version: 1
generated_at: YYYY-MM-DDTHH:MM:SS+09:00
commit_hash: (git rev-parse HEAD。Git未管理は N/A)
file_count: 数値
stack: スタック
stage: 段階
total_issues: 数値
critical: 数値
high: 数値
medium: 数値
low: 数値
---
```

本文構成: 概要テーブル → エグゼクティブサマリ(3〜5行) → 指摘サマリ(重大度×象限) → 前回比較(あれば) → [1]〜[4]象限別の指摘詳細(ID, ファイル:行, カテゴリ, 問題, 修正案diff, 工数, 根拠) → ドキュメント状況 → テスト状況 → 運用準備状況 → 推奨アクション(次の3ステップ) → 並列修正可能グループ → 次回注目ポイント。

指摘ゼロの場合も「問題なし」として全分析領域の結果をレポートに記録する。

**軽量モード** → コンソール出力（ファイルなし、最大20件）:

サマリ → [1]〜[4]象限別指摘 → 推奨アクション(次の3ステップ) → 未分析領域。
指摘ゼロ: 「改善提案なし。分析済み領域: [一覧]」と表示。

### 4-4. セルフレビュー

重大度分類の妥当性、修正計画の依存関係、見落としを確認。

### 4-5. 外部レビュー（フルモード、Critical/Highありの場合のみ）

Codex CLIが利用可能な場合、外部AI視点でのレビューを実行する:
```bash
codex exec --full-auto --sandbox read-only --cd "$(pwd)" \
  "このブランチの変更をレビューしてください。重大度（Critical/High/Medium/Low）、問題の説明、該当ファイル:行番号、修正提案を出力してください"
```
Codex CLI不在または実行失敗時はスキップし、セルフレビューのみで完了する。

### 4-6. ナレッジ候補の提示

レビュー結果から汎用知見としてkb-*に蓄積可能な指摘を「ナレッジ候補」として提示する:
```
## ナレッジ候補（/sync-knowledge用）
- C-003: [問題パターン] → [対象kb-*]
```
`/sync-knowledge --from-review` で自動反映可能。候補なしの場合はセクション省略。

---

## `--diff` モード

1. `docs/review-report.md` のYAMLフロントマターからcommit_hashを取得
2. `git diff --name-only <前回>..HEAD` で変更ファイルを特定
3. 変更ファイルのみフルレビュー実行
4. 前回指摘と照合: 解決済み / 未解決 / 新規を区別
5. レポート上書き

前回レポートなし → フルモードにフォールバック。

---

## エラーハンドリング

| 状況 | 動作 |
|------|------|
| サブエージェントエラー | 「未分析」として記録、残りの結果で出力 |
| スタック不明 | ユーザーに確認。指定なしなら汎用観点のみ |
| Git未管理 | `--staged`/`--recent`/`--diff`不可。commit_hash="N/A" |
| 軽量モードで指摘20件超 | 重大度順に20件に絞り残件数を記載 |
| linter失敗 | 手動Grepにフォールバック |
| CLAUDE.md不在 | 汎用ベストプラクティスのみで判定 |
| コンテキスト不足 | Grep各30件、Read各300行、指摘各15件に制限。調査済み/未調査範囲を明記 |

---

## 注意事項

- ソースコードは変更しない（レビューレポート`docs/review-report.md`の出力のみ）
- ドキュメントの作成・更新は行わない（過不足の指摘のみ）
- 未実装機能を「バグ」として報告しない（TODO/仕様と照合して区別）
- 指摘には必ず重大度・工数・根拠を含める
- 大規模プロジェクトはリスクベースでサンプリング（全ファイルは読まない）
- linter導入済みならその検出範囲は手動Grepしない
- プロジェクト段階に見合った提案のみ行い、改善の押し付けはしない
