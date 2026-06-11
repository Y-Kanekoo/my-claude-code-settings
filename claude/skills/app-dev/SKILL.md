---
name: app-dev
description: アプリ開発の全工程（理解→設計→実装→テスト→レビュー）を精度向上ワークフローの連結+人間チェックポイントで進める複合ハーネス
user-invocable: true
---

# app-dev 複合ハーネス

保存済みワークフロー（codebase-map / design-judge / test-gen / review-deep / bug-fix）をフェーズとして連結し、
フェーズ間に必ず人間チェックポイント（結果の要約提示→承認待ち）を挟んで開発を進める指揮者スキル。

## 進行手順

### Phase 0: 要件確認
- 引数や直前の会話から開発要件を把握する
- 曖昧な点（対象ユーザー・スコープ・技術制約・既存コードとの関係）があれば AskUserQuestion で2〜3問確認してから進む

### Phase 1: 理解（既存コードベースがある場合のみ）
- `Workflow` ツールで `{name: 'codebase-map'}`、args に `{focus: '<今回の開発に関係する領域>'}` を渡して実行
- 戻り値の map_md を要約して提示する（新規プロジェクトならこのフェーズはスキップ）

### Phase 2: 設計
- `Workflow` ツールで `{name: 'design-judge'}`、args に `{problem: '<要件の要約>', context_paths: [<関連パス>]}` を渡して実行
- **チェックポイント**: 最終設計書（final_design_md）と採点結果を提示し、ユーザーの承認を得るまで実装に進まない。修正要望があれば design-judge を再実行するか設計書を手直しして再提示する

### Phase 3: 実装
- 承認された設計の「実装順序の提案」をタスクに分解する（TaskCreate で追跡）
- タスクごとに: 実装 → テスト・lint 通過を確認 → 次のタスクへ
- 回復ルール: 同一エラー3回で異なるアプローチ、さらに3回でスキップ+TODO(autonomous)
- 実装中にバグが出たら `{name: 'bug-fix'}`、args `{bug: '<説明>'}` を使う

### Phase 4: テスト補強
- 主要モジュールごとに `{name: 'test-gen'}`、args `{target: '<モジュール>'}` を実行
- **チェックポイント**: mutation_score と weak_behaviors を提示する

### Phase 5: レビュー収束ループ
- `{name: 'review-deep'}`、args `{target: 'branch'}`（ブランチ作業でなければ `'diff'`）を実行
- confirmed の指摘を修正 → 再実行 → confirmed がゼロになるまで反復（最大3周。残った指摘は提示して判断を仰ぐ）

### Phase 6: 完了
- 変更サマリ・テスト結果・mutation_score・レビュー結果を報告し、コミットを提案する（承認なしにコミットしない）

## 原則

- チェックポイントを飛ばさない。各フェーズの結果は必ず要約して提示する
- 検証ゲート（テスト・lint・レビュー）を省略しない。自己申告の「完了」を信用しない
- ワークフローの名前解決に失敗する場合（セッション開始後に追加した直後）は `{scriptPath: '~/.claude/workflows/<name>.js'}` で起動する
- 規模を上げたいとき（精度勝負）はユーザーに `+300k` 等の budget 指定を案内する
