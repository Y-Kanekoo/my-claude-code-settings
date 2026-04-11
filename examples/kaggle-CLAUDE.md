# Kaggleプロジェクト共通設定

> グローバル設定・Projects/CLAUDE.mdを継承。重複ルール（並列処理・自律実行・日本語統一）は上位で定義済み。

## ディレクトリ構成
```
~/Projects/kaggle/
├── shared/                 ← 共通ライブラリ (pip install -e . で利用)
│   ├── kaggle_common/      ← Python パッケージ
│   └── check_new_playground.sh  ← 新コンペ通知スクリプト
├── playground-s6e3/        ← S6E3 (完了, 金メダル)
├── playground-s6e4/        ← S6E4 (進行中)
└── CLAUDE.md               ← この設定ファイル
```

## 共通ライブラリの使い方
各コンペディレクトリで:
```bash
uv add --editable ../shared
```
```python
from kaggle_common.ensemble import rank_average, optimize_weights, hill_climbing
from kaggle_common.utils import seed_everything, get_folds, save_oof, load_oof
from kaggle_common.features_common import encode_categories, oof_te_multi
```

## 各コンペディレクトリの標準構成
```
playground-s6eX/
├── src/           ← コンペ固有コード (config.py, data_loader.py, features.py)
├── scripts/       ← 実験スクリプト
├── data/          ← データセット (.gitignore)
├── oof/           ← OOF予測 (.gitignore)
├── submissions/   ← 提出ファイル (.gitignore)
└── pyproject.toml
```

## コンペ開始時のチェックリスト
1. `mkdir playground-s6eX && cd playground-s6eX`
2. `uv init && uv add --editable ../shared`
3. `uvx kaggle competitions download -c playground-series-s6eX -p data/`
4. `src/config.py` にコンペ固有設定
5. EDA → ベースライン → NB探索 → ブレンド

## Git運用
- **trunk 1本**（master直push）。コミット条件 = **再現可能な節目**
- push前に `validate_oof.sh` + `validate_submission.sh` を通す
- 詳細（タグ・Issue・PR・Gitに入れるもの）は `/kb-git` の「個人Kaggle向けGit運用」参照

## 定型作業の使い分け

| 種別 | ツール | 例 |
|------|--------|-----|
| 状態確認・データ処理 | Pythonスクリプト（トークン0） | `scripts/status.py`, `scripts/submit.py`, `scripts/mega_blend.py` |
| 判断・創造 | Claude直接実行 | 特徴量設計、戦略判断 |
| 多角的レビュー | サブエージェント並列 | `nb-review-*` 3種 |

新しい定型作業が発生したら → Pythonスクリプト化を検討

## バリデーション（事故防止）
- 提出前: `bash scripts/validate_submission.sh`
- OOF保存後: `bash scripts/validate_oof.sh`

## 品質ゲート

| ゲート | スクリプト | 基準 |
|--------|-----------|------|
| Champion-Challenger | `scripts/promote_candidate.py` | BA改善>0.0003 + fold分散非悪化 |
| Submission Gate | `scripts/submission_gate.py` | バリデーション通過 + champion比較 |
| Score Uncertainty | `scripts/score_uncertainty.py` | bootstrap信頼区間で有意性検証 |

詳細は `/kb-patterns` の「Kaggleハーネスゲート」参照

## エスカレーションラダー
L1(CLAUDE.md) → L2(エージェント検証) → L3(バリデーションスクリプト) → L4(PostToolUseフック)。
詳細・実例は `/kb-patterns` の「エスカレーションラダー」参照

## サブエージェント
- 登録基準: 2回以上同じ指示で起動 or 複数コンペで再利用するパターン
- 一覧・詳細は `/kb-kaggle` の「サブエージェント登録基準」参照

## テンプレート

| テンプレート | パス | 用途 |
|------------|------|------|
| EDA+ベースラインNB | `shared/templates/nb_eda_baseline.ipynb` | 新コンペ開始時のNB雛形 |

## 新コンペ通知
毎日9:00にPlayground Series新コンペをチェック (launchd)。手動: `bash shared/check_new_playground.sh`
