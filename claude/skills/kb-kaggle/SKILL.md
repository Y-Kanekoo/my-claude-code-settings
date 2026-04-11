---
name: kb-kaggle
description: Kaggleコンペの汎用ナレッジベース。モデル選択、アンサンブル、特徴量パターンを蓄積
user-invocable: true
entry_count: 19
last_updated: 2026-04-11
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

### 1.2 LightGBM

**状況**: 大規模テーブルデータのデフォルト選択肢
**強み**: 最速。疎なデータ・高カーディナリティに強い。カテゴリ変数ネイティブ対応
**弱み**: 小規模データで過学習しやすい（leaf-wise特性）。外れ値に敏感。`num_leaves`の感度が高い

**推奨パラメータ範囲**:
```python
LGB_PARAMS = {
    "objective": "binary",        # or "regression"
    "metric": "auc",              # or "rmse"
    "boosting_type": "gbdt",
    "learning_rate": 0.01~0.1,    # 最終提出は低め(0.01~0.03)、探索は高め(0.05~0.1)
    "num_leaves": 20~100,         # 2^max_depth より小さくする
    "max_depth": 3~8,             # 大規模データでも浅め(3~5)が有効な場合あり
    "min_child_samples": 10~100,
    "subsample": 0.5~0.9,
    "colsample_bytree": 0.3~0.9,
    "reg_alpha": 0~10,            # L1正則化
    "reg_lambda": 0~10,           # L2正則化
    "n_estimators": 3000~10000,   # early_stoppingと併用
}
```

**GPU設定**:
```python
params["device"] = "gpu"
```

### 1.3 XGBoost

**状況**: 安定性を重視する場合の選択肢
**強み**: 3段階の正則化で汎化性能が最も安定。ノイズに強い
**弱み**: カテゴリ変数のネイティブ対応が弱い。特徴量が多すぎるとノイズに弱い（多くの派生特徴量を入れると劣化する場合がある）

**推奨パラメータ範囲**:
```python
XGB_PARAMS = {
    "objective": "binary:logistic",  # or "reg:squarederror"
    "eval_metric": "auc",
    "tree_method": "hist",           # GPU: "gpu_hist"
    "learning_rate": 0.01~0.1,
    "max_depth": 3~8,
    "min_child_weight": 1~100,
    "subsample": 0.5~1.0,
    "colsample_bytree": 0.3~1.0,
    "reg_alpha": 0~10,
    "reg_lambda": 0~10,
    "gamma": 0~5,                    # 分割最小ゲイン
    "n_estimators": 3000~10000,
}
```

**注意**: XGBoost 3.x では early stopping は callbacks API で指定する
```python
import xgboost as xgb
callbacks = [
    xgb.callback.EarlyStopping(rounds=200, save_best=True),
    xgb.callback.EvaluationMonitor(period=100),
]
model = xgb.XGBClassifier(**params, callbacks=callbacks)
```

**GPU設定**:
```python
params["tree_method"] = "gpu_hist"
params["device"] = "cuda"
```

### 1.4 CatBoost

**状況**: カテゴリ変数が多いデータ、チューニング工数を抑えたい場合
**強み**: カテゴリ処理が最強（前処理不要）。Ordered Boostingでリーク防止。チューニング少なくても高精度。GPU学習がGBDT中最速
**弱み**: CPU学習が遅い。メモリ消費大。カテゴリ列はint型必須（float不可、事前変換が必要）

**推奨パラメータ範囲**:
```python
CAT_PARAMS = {
    "loss_function": "Logloss",     # or "RMSE"
    "eval_metric": "AUC",
    "learning_rate": 0.01~0.1,
    "depth": 4~10,
    "l2_leaf_reg": 1~10,
    "min_data_in_leaf": 1~100,
    "random_strength": 0~10,        # 分割のランダム性
    "bagging_temperature": 0~1,     # ベイジアンブートストラップ
    "iterations": 3000~10000,
}
```

**CatBoostのカテゴリ処理の注意点**:
```python
from catboost import Pool
# カテゴリ列をint型に変換してからPoolに渡す
for col in cat_cols:
    df[col] = df[col].astype(int)
pool = Pool(X, y, cat_features=cat_feature_indices)
```

**GPU設定**:
```python
params["task_type"] = "GPU"
params["devices"] = "0"
```

### 1.5 補助モデル

| モデル | 用途 | 適性 |
|--------|------|------|
| Ridge / Logistic Regression | スタッキングメタモデル、N-gram Ridge | スタッキングL2、テキスト的特徴量 |
| Random Forest / ExtraTrees | ベースライン、アンサンブルの多様性 | 過学習しにくいベースライン |
| TabPFN | メタ学習済みTransformer | 1万行以下で最強クラス。大規模データには不向き |
| FT-Transformer | 特徴量をトークン化してTransformer処理 | 中規模データ、アンサンブルの多様性要員 |
| TabNet | Attention機構で特徴量選択 | GPU環境、中〜大規模データ |

### 1.6 Optunaチューニングの知見

**状況**: 3モデルともチューニングで共通の傾向が出ることが多い
**パターン**:
- 大規模データ（数十万行以上）でも**浅い木（depth 3〜5）が最適**な場合がある
- 学習率はデフォルト（0.01〜0.03）より高め（0.04前後）に収束することがある
- 正則化の手段はモデルごとに異なるが、何らかの正則化は常に有効

---

## 2. アンサンブル戦略

### 2.1 手法比較

| 手法 | 特徴 | 実装 |
|------|------|------|
| 単純平均 | 最もシンプル。まず試す | `np.mean([pred1, pred2, pred3], axis=0)` |
| 加重平均 | Optunaで最適重みを探索 | `sum(w*p for w,p in zip(weights, preds))` |
| Rank平均 | 予測スケールの違いを吸収 | `scipy.stats.rankdata(pred) / len(pred)` |
| スタッキング | L1のOOF予測をL2メタモデルに入力 | Ridge/LGB/MLPで学習 |
| Hill Climbing | 貪欲法で最適モデル選択 | 毎ラウンド最良モデルを追加 |

### 2.2 アンサンブルが効く条件

**多様性が最重要**: 異なるアルゴリズム > 異なるパラメータ > 異なるseed
- 同モデル・seed違い: 相関 0.98〜0.99 → 効果小
- 異モデル（LGB vs XGB vs CAT）: 相関 0.93〜0.96 → 効果中
- GBDT vs NN/Ridge: 相関 0.85〜0.92 → 効果大

**相関チェックのコード**:
```python
from scipy.stats import spearmanr
corr, _ = spearmanr(oof_a, oof_b)
# 0.95以下が理想。0.98+は追加する意味が薄い
```

### 2.3 モデル数の目安

| モデル数 | 費用対効果 |
|----------|-----------|
| 3〜5 | 最も効率的なゾーン |
| 5〜10 | 改善は小さくなるが金メダル圏では重要 |
| 10+ | 管理コストが高い。僅差の勝負用 |

### 2.4 良い組み合わせパターン

**定番**: LightGBM + XGBoost + CatBoost（分割戦略が全て異なる）
**拡張**: 各モデル × 3seed = 9モデル平均（ランダム性を吸収）
**最強**: GBDT + Ridge N-gram（学習原理が根本的に異なる）
**金メダル狙い**: GBDT + NN系（TabNet/FT-Transformer）+ 線形モデル → スタッキング

### 2.5 悪い組み合わせパターン

**状況**: アンサンブルが逆効果になるケース
- 精度が大きく劣るモデルを混ぜる（最良比 -0.02以上差があると足を引っ張る）
- 過学習モデル同士（ノイズを平均しても改善しない）
- 相関 0.98+ のモデル同士（多様性がない）
- 弱いモデルが多数派になる加重なし平均

---

## 3. 特徴量エンジニアリングパターン

### 3.1 カテゴリ変数

| 手法 | 実装 | 適性 |
|------|------|------|
| Label Encoding | `LabelEncoder().fit_transform()` | GBDT全般。train+testでfit |
| Target Encoding | fold内trainのみからターゲット統計量を算出 | 予測力が高いがリーク注意 |
| Frequency Encoding | `value_counts(normalize=True)` | trainの頻度をtestにmap |
| N-gram | カテゴリをテキスト化 → CountVectorizer | Ridge/線形モデルとの組み合わせに有効 |
| 交互作用 | `col_a + "_" + col_b` → Label Encoding | カテゴリ間の組み合わせを捕捉 |

**Target Encodingのリーク防止**:
```python
# OOF方式: fold内のtrainのみから統計量を計算してvalにmap
for train_idx, val_idx in folds:
    agg = train.iloc[train_idx].groupby(col)[target].mean()
    train.iloc[val_idx, te_col] = train.iloc[val_idx][col].map(agg)
# testには全trainから計算した値をmap
```

**スムージング**:
```python
smooth_mean = (cat_mean * cat_count + global_mean * smoothing) / (cat_count + smoothing)
# smoothing=10〜50 が一般的。低頻度カテゴリの過学習を緩和
```

### 3.2 数値変数

| 手法 | 例 | 用途 |
|------|-----|------|
| 対数変換 | `np.log1p(x)` | 右裾の重い分布の正規化 |
| ビニング | `pd.cut(x, bins=[...])` | 非線形関係の簡素化 |
| 交互作用 | `x1 * x2`, `x1 / (x2 + 1e-8)` | 変数間の関係を明示 |
| Groupby統計量 | `groupby(cat)[num].agg(['mean','std'])` | カテゴリ別の数値傾向 |
| パーセンタイルランク | `rankdata(x) / len(x)` | スケール正規化 |
| Zスコア | `(x - mean) / std` | グループ内の相対位置 |
| 分位点距離 | 正例/負例のQ25/Q50/Q75との距離 | ターゲットとの関係を捕捉 |

**Groupby統計量のリーク防止**: trainの統計量をtestにmap。testに未知カテゴリがある場合はtrain全体のagg値で埋める

### 3.3 N-gram Ridge パイプライン

**状況**: カテゴリ変数が多いテーブルデータで、GBDTとは異なる予測パターンを作りたい
**解決策**: カテゴリを空白区切りのテキストに結合 → CountVectorizer → Ridge → sigmoid

```python
# 1. カテゴリをテキスト化
text = df[cat_cols].astype(str).apply(lambda row: " ".join(row), axis=1)

# 2. N-gram化
from sklearn.feature_extraction.text import CountVectorizer
vec = CountVectorizer(analyzer="word", ngram_range=(2,3), max_features=500)
X_sparse = vec.fit_transform(text)

# 3. Ridge学習 → sigmoid変換
from sklearn.linear_model import Ridge
model = Ridge(alpha=10.0)
model.fit(X_train, y_train)
pred = 1.0 / (1.0 + np.exp(-model.predict(X_test)))
```

**効果**: GBDTとの相関が低い（0.85〜0.92）ため、アンサンブル効果が大きい。Ridge単体のAUCが低くても（例: 0.888）、GBDTの特徴量に追加すると全体スコアが大幅改善する場合がある

### 3.4 特徴量の量と質

**状況**: 特徴量を増やしすぎると逆効果になる
**パターン**:
- 全カテゴリ交互作用を網羅（数百特徴量）→ ノイズ増加でスコア低下
- 厳選した交互作用（5〜10ペア）→ 安定した改善
- モデルによって適切な特徴量数が異なる（XGBoostは少なめが安定、LGBMは多めでもOK）

---

## 4. CV戦略

### 4.1 fold数の使い分け

| fold数 | 特徴 | 用途 |
|--------|------|------|
| 5-fold | 高速。探索フェーズ向き | ハイパーパラメータ探索、特徴量選択 |
| 10-fold | バランス型 | 本番訓練のデフォルト |
| 20-fold | 低分散。最終提出向き | 最終モデル、BlamerX手法 |

### 4.2 seed平均

**状況**: 同じモデル・パラメータでもseedによってスコアが微妙に異なる
**解決策**: 複数seed（3〜10個）で訓練して予測を平均化

```python
seeds = [42, 123, 456]
avg_pred = np.mean([train_and_predict(seed=s) for s in seeds], axis=0)
```

**効果**: +0.0001〜0.0003 程度の改善。微小だが安定
**推奨**: まず3seed（42, 123, 456）から。金メダル狙いなら10seed

### 4.3 CV-LBギャップ

**状況**: ローカルCVとLeaderboardスコアの乖離
**対策**:
- CVが安定しているモデルを信頼する（CV分散が小さい方が信頼性高い）
- LBに過度に合わせない（overfitting to public LB のリスク）
- CV改善とLB改善が一致する施策を優先する

---

## 5. Kaggle Playground Series 固有の知見

### 5.1 元データ（original）の扱い

**状況**: Playground Seriesは実データをベースに合成データを生成している。元データが公開されている場合がある
**パターン**:
- 合成データのみで訓練した方がスコアが良い場合がある
- 元データと合成データの分布差がノイズになる
- 元データを使う場合は重みを下げる（sample_weight）ことで緩和可能

### 5.2 合成データの特性

- SDV（Synthetic Data Vault）等で生成されたデータ
- カテゴリの組み合わせパターンが実データより均一化される傾向
- 稀なカテゴリの出現頻度が変わる場合がある

---

## 6. 実験管理パターン

### 6.1 experiment_log.csv

**状況**: 実験結果を追跡可能にしたい
**フォーマット**:
```csv
timestamp,experiment,oof_auc,details
2026-03-26 01:11:46,xgb_v2,0.915797,"folds=10, seed=42, features=58"
```

**記録すべき情報**: タイムスタンプ、実験名、CVスコア、fold数、seed、特徴量数、主要パラメータ変更点

### 6.2 OOF予測の保存・命名規則

```
oof/
├── {model}_{set}_{seed}_oof.npy    # OOF予測（train）
├── {model}_{set}_{seed}_test.npy   # テスト予測
└── best_params_{model}.json         # Optuna最適化結果
```

**例**: `lgb_a_s42_oof.npy` = LightGBM, Set A, seed=42 の OOF予測

**重要**: OOFとテスト予測は必ずペアで保存する。後からアンサンブルに使用するため

### 6.3 提出戦略

- 毎日の提出回数制限に注意（通常5回/日）
- 最終的に2つの提出を選択できる（public/private split を考慮）
- CV最良モデルとアンサンブル最良を1つずつ選ぶのが安全
- Rank平均は順位に基づくため、予測分布の違いを吸収でき提出に適している

### 6.4 プロジェクト構成テンプレート

```
project/
├── data/              # 入力データ（.gitignore推奨）
│   ├── train.csv
│   ├── test.csv
│   └── original/      # 元データ
├── src/               # 共有モジュール
│   ├── config.py      # 定数・パラメータ一元管理
│   ├── data_loader.py # データ読み込み
│   ├── features.py    # 特徴量エンジニアリング
│   ├── models.py      # 統一モデルインターフェース
│   └── ensemble.py    # アンサンブル・重み最適化
├── scripts/           # 実験スクリプト（番号付き）
│   ├── 01_baseline.py
│   ├── 02_train_model.py
│   └── ...
├── oof/               # OOF予測・パラメータ保存
├── submissions/       # 提出CSV
├── docs/              # プロジェクト固有ドキュメント
├── experiment_log.csv # 実験ログ
└── pyproject.toml     # 依存関係
```

---

## 7. 多クラス分類の知見

### 7.1 GBDTの多クラスパラメータ

バイナリ分類からの主要変更点:

| 項目 | LightGBM | XGBoost | CatBoost |
|------|----------|---------|----------|
| objective | `multiclass` | `multi:softprob` | `MultiClass` |
| metric | `multi_logloss` | `mlogloss` | `MultiClass` |
| 追加パラメータ | `num_class: N` | `num_class: N` | 不要（自動検出） |
| predict_proba出力 | `(n, N_classes)` | `(n, N_classes)` | `(n, N_classes)` |

```python
# LightGBM
LGB_PARAMS = {"objective": "multiclass", "metric": "multi_logloss", "num_class": 3, ...}

# XGBoost
XGB_PARAMS = {"objective": "multi:softprob", "eval_metric": "mlogloss", "num_class": 3, ...}

# CatBoost
CAT_PARAMS = {"loss_function": "MultiClass", "eval_metric": "MultiClass", ...}
```

### 7.2 OOF予測の形式

**バイナリ**: `np.zeros(n_samples)` — 1D配列（正例確率）
**多クラス**: `np.zeros((n_samples, n_classes))` — 2D配列（各クラスの確率）

```python
# バイナリ
oof_preds[val_idx] = model.predict_proba(X_val)[:, 1]
test_preds += model.predict_proba(X_test)[:, 1] / n_folds

# 多クラス
oof_preds[val_idx] = model.predict_proba(X_val)  # shape: (val_size, n_classes)
test_preds += model.predict_proba(X_test) / n_folds  # shape: (test_size, n_classes)
```

`np.save` / `np.load` は2D配列にそのまま対応するため、保存・読み込みコードの変更は不要。

### 7.3 評価指標

- **accuracy**: `accuracy_score(y_true, oof_preds.argmax(axis=1))` — 提出がラベル文字列の場合の主指標
- **macro-F1**: `f1_score(y_true, oof_preds.argmax(axis=1), average="macro")` — 不均衡データの補助指標
- **log_loss**: `log_loss(y_true, oof_preds)` — 確率の品質評価。early stoppingにはこちらを使用

### 7.4 多クラスアンサンブル

**加重平均**: `np.zeros_like` が2Dに自動対応するため、バイナリと同じコードで動作

**ランク平均**: **クラスごとに独立してrank変換する必要がある**
```python
# 正しい多クラスrank_average
for pred in predictions_list:
    ranked = np.zeros_like(pred)
    for c in range(n_classes):
        ranked[:, c] = rankdata(pred[:, c]) / n_samples
    # 加重平均
```

**重み最適化**: `accuracy_score(y_true, blended.argmax(axis=1))` で最適化。`roc_auc_score` は使えない

**提出ファイル**: `argmax` → ラベル文字列（LabelEncoderの `inverse_transform` またはクラス名リストでマッピング）

### 7.5 kaggle_common のバイナリ→多クラス変換チェックリスト

共有ライブラリをプロジェクトローカルにコピーして多クラス化する際の変更箇所:

1. `predict_proba(X)[:, 1]` → `predict_proba(X)` （全箇所）
2. `np.zeros(len(X))` → `np.zeros((len(X), N_CLASSES))` （OOF/test配列）
3. `roc_auc_score` → `accuracy_score` + `log_loss` （評価）
4. デフォルトパラメータの `objective` / `metric` を多クラス用に変更
5. `create_submission`: 確率→ラベル文字列への変換ロジック追加
6. `rank_average`: クラスごとの独立rank変換
7. `LGBMClassifier` → そのまま（`objective="multiclass"` で自動対応）
8. `XGBClassifier` → そのまま（`objective="multi:softprob"` で自動対応）
9. `CatBoostClassifier` → そのまま（`loss_function="MultiClass"` で自動対応）

---

## 8. ノートブック公開戦略

### 8.1 メダル基準

| メダル | 必要投票数 | 備考 |
|--------|-----------|------|
| 銅（Bronze） | 5票以上 | Noviceランクの票は除外 |
| 銀（Silver） | 20票以上 | |
| 金（Gold） | 50票以上 | |

**Progression要件**: Expert=銅5個 / Master=銀10個 / Grandmaster=金15個
**メダル交換制度はない**: 銅を集めても銀・金にはならない。ただし銅5個でExpert称号

### 8.2 金メダルを狙うパターン

| パターン | 有効性 | 適性 |
|----------|--------|------|
| EDA + ベースライン統合型 | 最も高い | コンペ序盤。初心者の需要大 |
| 元データ分析（Playground限定） | 高 | 競合少なく差別化しやすい |
| 高スコア解法 | 高 | スコアが信頼の証。ただし手の内を明かす |
| アンサンブル/ブレンド解説 | 中〜高 | 中上級者向け。教育的価値が必要 |
| AutoML紹介 | 中 | インパクトはあるが深みに欠ける |

### 8.3 先行者利益

- **最初の数時間で20票**獲得するとKaggleアルゴリズムで上位表示→正のフィードバックループ
- 同じ内容でも先に出した人にvoteが集中し、後発は埋もれる
- **コンペ開始直後が最高のタイミング**
- 投稿曜日: 火〜木の午後（米国東部時間）が最もトラフィック多い

### 8.4 複数NB戦略

- テーマ別に出せば票は分散しない（読者層が異なる）
- Chris Deatteは1エピソードで5本の金メダルを獲得した実績
- Ravi Ramakrishnanは毎回「EDA」「Baseline」「AdversarialCV」と複数投稿
- ambrosm は「EDA which makes sense」シリーズでブランド化（毎回金メダル）

### 8.5 公開時の注意点

- **スコアを温存する**: 公開NBは意図的に弱い設定にする（fold数↓、lr↑、特徴量↓）
- **キーとなるトリックを隠す**: Groupby統計量、交互作用、後処理は非公開に
- **評価指標を明記**: Balanced Accuracy等、コンペ固有の指標をタイトルや本文に含める
- **upvoteの呼びかけ（CTA）**: 冒頭と末尾に「If helpful, please upvote 👍」を入れる

### 8.6 常連金メダリストの特徴

| 著者 | 戦略 | PGS最高votes |
|------|------|-------------|
| Chris Deotte | GPU活用・高スコア解法 | 448 |
| Satya | 毎回EDA+モデル統合型 | 480 |
| ambrosm | シリーズ化でブランド構築 | 336 |
| Ravi Ramakrishnan | テーマ別複数投稿 | 249 |
| Masaya Kawamata | Competition Starter型 | 263 |

---

## 9. ノートブック書き方テンプレート

### 9.1 構成テンプレート（EDA + ベースライン型）

```
# タイトル（絵文字 + コンペ名 + 内容 + スコアor指標名）
例: 🌾 S6E4 | Comprehensive EDA + LightGBM Baseline | Balanced Accuracy

## 冒頭セクション
- コンペへのリンク
- 評価指標の明示
- 内容の箇条書き（📊 EDA、🔍 分析、🤖 モデル、📈 結果）
- Table of Contents（表形式）
- upvote呼びかけ 👍

## 1. Setup & Data Loading
- ライブラリimport（コメント付き）
- データ読み込み（shape表示）

## 2. Target Distribution
- 「なぜこれを見るのか」を冒頭に説明
- 棒グラフ + 円グラフ（カラーパレット統一）
- 数値ラベル付き
- Key Takeaway（💡アイコン付き）

## 3-7. 特徴量分析
- 各セクション冒頭に「何を確認するか」の説明
- 可視化の後に「💡 Key Findings」で箇条書きの要点
- ドメイン知識を活かしたInsight（「物理的に理にかなっている」等）
- 改善のヒント（「特徴量エンジニアリングに使えそう」等）

## 8. 評価指標の解説（教育的価値）
- なぜこの指標が重要か
- 計算式
- 実践的な意味合い

## 9. モデル訓練
- パラメータの意味をコメントで説明
- CV結果の表示

## 10. 結果分析
- Confusion Matrix
- Classification Report
- Feature Importance

## 11. 提出

## 🚀 改善のアイデア
- 具体的な次のステップ（3カテゴリ: Feature Engineering / Modeling / Data）
- 自分の他のNBへのリンク
- upvote呼びかけ + fork推奨
```

### 9.2 金メダルNBの書き方ルール

**タイトル**:
- 絵文字で始める（🌾🔬📊等）
- コンペ名（S6E4等）を含める
- スコアがあれば明示（`| LB 0.970`）
- 内容のキーワード（EDA, Baseline, Ensemble等）

**コード**:
- 全てのコードブロックに `#` コメントで「なぜこれをするか」を説明
- マジックナンバーにはコメント（`N_FOLDS = 5  # 5-fold for speed`）
- 変数名は自己説明的に

**可視化**:
- カラーパレットは統一（Low=緑, Medium=橙, High=赤 など意味のある配色）
- グラフに数値ラベル・アノテーションを付ける
- タイトルは `fontweight='bold'`、fontsize=14
- `edgecolor='white'` で棒グラフを見やすく

**Markdown**:
- 各セクション冒頭に「読み手への問いかけ」（「では分布の偏りはどの程度か見てみましょう」）
- 分析結果の後に「💡 Key Findings」で要点をまとめる
- ドメイン知識の解説（「土壌水分が低い→灌漑必要は物理的に当然」）
- 次のアクションへのヒント

**読み手目線の原則**:
- 読み手は「このコンペに参加したばかりで、データの理解を深めたい人」
- 「なぜ」を常に説明する（コードの意図、分析の目的、結果の解釈）
- 専門用語は初出時に簡単に説明
- グラフだけ見ても要点がわかるようにする

---

## 10. Balanced Accuracy最適化

### 10.1 閾値最適化（最も費用対効果が高い）

**状況**: 評価指標がBalanced Accuracyの場合、`argmax`は最適ではない
**解決策**: 各クラスにバイアスを加算してからargmax

```python
def optimize_thresholds(oof_proba, y_true, n_trials=2000):
    """クラスごとのバイアスをOptunaで最適化"""
    # biases = [0, b1, b2]（クラス0を基準）
    # adjusted = proba + biases
    # pred = adjusted.argmax(axis=1)
    # → balanced_accuracy_score(y_true, pred) を最大化
```

**S6E4実績**: +0.003 BA改善（0.9627→0.9656）。少数クラス(High=3.3%)の予測バイアスを上げることでRecallが改善
**注意**: OOF上での最適化はLBでも効果が確認された（CV-LB一致）

### 10.2 class_weight='balanced'

**状況**: 少数クラスのRecallが低い場合
**解決策**: 訓練時にクラス重みを逆頻度で設定

```python
# LightGBM
LGBMClassifier(class_weight='balanced', ...)

# XGBoost（多クラスはsample_weight経由）
from sklearn.utils.class_weight import compute_sample_weight
sample_weights = compute_sample_weight('balanced', y)
model.fit(X_train, y_train, sample_weight=w_train)

# CatBoost
from sklearn.utils.class_weight import compute_class_weight
weights = compute_class_weight('balanced', classes=np.unique(y), y=y)
CatBoostClassifier(class_weights=list(weights), ...)
```

**S6E4実績**: LGB BA +0.004（0.9624→0.9667）、XGB BA +0.006（0.9625→0.9686）。閾値最適化と組み合わせてCV BA 0.9704達成

### 10.3 class_weightとバイナリの違い

| 手法 | バイナリ分類 | 多クラス分類 |
|------|------------|------------|
| 閾値最適化 | 単一閾値 (0-1) | クラス別バイアス |
| class_weight | `scale_pos_weight` | `class_weight='balanced'` or sample_weight |
| 評価指標 | AUC → 閾値不要 | BA → 閾値最適化が重要 |

---

## 11. 計算リソースの活用

### 11.1 計算リソース一覧

| リソース | CPU/GPU | メモリ | 制限 | 最適なモデル |
|----------|---------|--------|------|------------|
| **ローカル Mac** | M4 Pro 14コア + **MPS 20コアGPU** | **48GB共有** | 制限なし | GBDT全般 + DLモデル(MPS) |
| **Kaggle Notebook** | T4 × 2 (CUDA) | 32GB + 32GB VRAM | 30h/週 | CUDA専用(TabR, cuML) |

### 11.2 MPS GPU活用ガイド（Apple Silicon）

**性能**: ~4,500 GFLOPS (FP32)。NVIDIA T4の約60%の演算性能だが、48GB共有メモリは圧倒的

**制約と回避策**:
- INT_MAX制限 → micro-batch (2048) + gradient accumulation
- 非対応op → `PYTORCH_ENABLE_MPS_FALLBACK=1` でCPUフォールバック
- fold間で `torch.mps.empty_cache()` を挿入
- `num_workers=0〜4`（過多は逆効果）

**使い分け**:
- **MPS**: DLモデル量産(TabM/RealMLP/TabNet)、ハイパラ探索、OOF生成
- **Kaggle T4**: CUDA専用モデル(TabR/cuML)、最終再学習、NB公開
- **CPU**: GBDT系（LGB/XGB/CAT/HGB）、後処理、ブレンド最適化

### 11.2 Kaggle GPU訓練のAPI自動化

```bash
# kernel-metadata.jsonで "enable_gpu": true を指定
# push → ステータス監視 → 完了通知 → OOFダウンロード
uv run python scripts/kaggle_gpu_train.py auto tabm
```

**ポイント**:
- `is_private: true` で非公開実行（GPU quota消費）
- `competition_sources` でコンペデータをマウント（パスは `/kaggle/input/competitions/{slug}/`）
- OOFは `/kaggle/working/` にnpy/csv出力し、`kaggle kernels output` でダウンロード
- 完了時にmacOS通知を送信

### 11.3 Macメモリについて

- Apple Silicon (LPDDR5) はDRAMのため書き込み劣化なし
- 長時間高負荷では熱スロットリングのみ（冷えれば回復）
- 48GBあれば630K行のGBDT訓練でスワップはほぼ発生しない

---

## 12. モデル単体精度ランキング (2025年)

### 12.1 ベンチマーク順位（TabArena 2025）

| 順位 | モデル | カテゴリ | データサイズ適性 |
|------|--------|---------|---------------|
| 1 | CatBoost | GBDT | 全サイズで最強（単体チューニング時） |
| 2 | TabPFN v2 | Foundation | ~10K行で圧倒的 |
| 3 | TabM | DL | 中規模で強い（ICLR 2025） |
| 4 | RealMLP | DL | 中規模で強い |
| 5 | LightGBM | GBDT | 大規模で最速 |
| 6 | XGBoost | GBDT | 安定性最高 |

**上位6モデル間に統計的有意差はない**

### 12.2 アンサンブル用モデルTier分類

| Tier | モデル | GBDTとの相関 | 実装難易度 | CPU実現性 |
|------|--------|-------------|-----------|----------|
| S | LGB/XGB/CAT | 0.93-0.96 | ★ | ○ |
| A | N-gram Ridge | 0.85-0.92 | ★ | ○（数秒） |
| A | sklearn MLP | 0.85-0.92 | ★ | ○ |
| A | RealMLP | 0.85-0.90 | ★★ | ○ |
| B | TabNet | 0.87-0.93 | ★★ | ○（1-2h） |
| B | TabM | 0.85-0.90 | ★★★ | △（GPU推奨） |
| B | HGB | 0.97 | ★ | ○ |
| C | FT-Transformer | 0.85-0.90 | ★★★ | ✕ |
| D | TabPFN | — | ★★ | 50K行上限 |
| D | SAINT/NODE/KNN | — | ★★★ | ✕ |

---

## 13. パイプライン自動化

### 13.1 トークン消費なしのPythonスクリプト

| スクリプト | 用途 |
|-----------|------|
| `scripts/status.py` | LB順位、OOF状況、訓練プロセス一括表示 |
| `scripts/submit.py` | Kaggle提出 + スコア確認 |
| `scripts/mega_blend.py` | 全OOFブレンド + 閾値最適化 |
| `scripts/kaggle_gpu_train.py` | Kaggle GPU訓練の自動化 |

### 13.2 サブエージェント

| エージェント | 用途 | タイミング |
|-------------|------|-----------|
| `pipeline-builder` | パイプライン一括構築 | コンペ開始時 |
| `model-researcher` | モデル候補調査 | OOF蓄積後 |
| `accuracy-improver` | 自律精度改善 | スコア停滞時 |
| `nb-auto-fetch-blend` | 公開NB取得+ブレンド | コンペ中盤 |
| `nb-review-*` (3体) | NBレビュー（読みやすさ/可視化/マーケ） | NB公開前 |

### 13.3 テンプレート

- `shared/templates/nb_eda_baseline.ipynb` — プレースホルダー付きNBテンプレート（31セル）
- `sed` 等で `{COMP_SLUG}`, `{TARGET_COL}`, `{METRIC}` 等を一括置換して使う

---

## 14. S6E4で得た知見（次コンペへの参考）

### 14.1 Balanced Accuracyコンペの最適戦略

1. **class_weight='balanced' が最優先** — 通常訓練からBA +0.004-0.006の改善
2. **閾値最適化が次に効果的** — 追加で+0.003
3. **両方の組み合わせで最大効果** — 通常BA 0.962 → balanced+閾値 0.970（+0.008）

### 14.2 Kaggle API の注意点

- `competition_sources` でのデータマウントパスは `/kaggle/input/competitions/{slug}/`（UIとは異なる）
- パス自動検出ロジックを入れると安全:
```python
DATA_DIR = f'/kaggle/input/{COMP}'
if not os.path.exists(DATA_DIR):
    DATA_DIR = f'/kaggle/input/competitions/{COMP}'
```

### 14.3 Chris Deotte S6E3 1位手法（KGMON Playbook）

**規模**: 850モデル → 150選別 → 4段スタック。LLM（GPT/Gemini/Claude）で60万行のコードを自動生成。

**最重要特徴量テクニック**:

1. **Snap Features（最近傍マッピング）**: 合成データの値を元データの最近傍値にスナップし、差分（合成ノイズ量）を特徴量化
```python
orig_vals = np.sort(original[col].unique())
idx = np.searchsorted(orig_vals, df[col].values)
snap_vals = orig_vals[np.clip(idx, 0, len(orig_vals)-1)]
df[f"{col}_snap_diff"] = df[col] - snap_vals
```

2. **小数桁抽出（Decimal Digit Features）**: 合成データ生成器の丸め痕跡を捉える
```python
frac = df[col] - np.floor(df[col])
df[f"{col}_d1"] = np.floor(frac * 10).astype(int)   # 小数第1位
df[f"{col}_d2"] = (np.floor(frac * 100) % 10).astype(int)  # 小数第2位
```

3. **cKDTree Lookup**: 元データの最近傍サンプルのターゲットを特徴量に
```python
from scipy.spatial import cKDTree
tree = cKDTree(orig_normalized)
dists, idxs = tree.query(train_normalized, k=3)
df["nn_target_mean"] = y_orig[idxs].mean(axis=1)
```

4. **Nested TE統計量**: mean以外にstd/min/max/medianも計算（元データで算出→リークなし）

5. **全ペア交互作用 + TE**: 全列ペアを文字列結合し、ユニーク値>50%を除外、sklearn TargetEncoder(multiclass)で変換

6. **ドメイン知識算術特徴量**: 蒸発ストレス`(Temp×Wind)/(Humidity+1)`、水収支、乾燥指数等

**アンサンブル**: 4段スタック。Level 4はcuML L2 Logistic Regression。モデル選択はGreedy Forward Selection (Hill Climbing)。

**LLM活用**: 人間がPlaybook（方法論）を策定し、LLMがコードを生成・実行。1ヶ月で850モデルを構築。我々のClaude Code活用と本質的に同じアプローチ。

### 14.4 公開NBの活用戦略（S6E4で実証）

**最も効果的な方法は「自前モデルを増やす」ではなく「高スコア公開NBの確率予測を活用する」**

- 公開NBのOOF/test予測（確率配列）をダウンロードし、閾値最適化を適用
- 異なるモデルタイプ（XGB + LR等）のOOFをブレンド → 相関が低いほど効果大
- hard label（submission.csv）の投票ブレンドは効果薄（不一致率0.5-0.95%）
- OOF/probaがないNBはコードを再実行してOOFを取得するのが理想

**S6E4実績**:
- 自前21モデルのベスト: LB 0.97015
- mahog(LB 0.976) + 閾値最適化: LB 0.97685 (+0.007)
- mahog XGB + mahog LR + 閾値最適化: LB **0.97707** (+0.007)
- 自前nb1_exactを混ぜるとLBが下がる（同じ手法なので相関が高すぎる）

**教訓**: 自前モデルの精度向上より、高スコア公開NBとの低相関ブレンドが圧倒的に費用対効果が高い

### 14.5 NB公開の教訓

- API pushでのERROR → パス問題が最多原因
- 先行者利益は24時間で大幅減衰
- 実行エラーのNBはvoteが付かない → 最初の投稿で成功させることが重要
- NB v2以降の更新ではタイトル変更も反映可能

## 15. CV-LB天井現象とブレンド重み戦略

### 現象
外部NB OOFの重み最適化でCV BAを+0.0017改善しても、LBは改善しない（むしろ悪化）ことがある。

### 原因
- Optuna重み最適化がCVのノイズに過学適合
- 閾値最適化（バイアス項追加）もCV上は改善するがLBでは逆効果の場合あり
- 高品質な単体モデルにノイズの多いモデルを混ぜると精度低下

### 対策
1. **均等ブレンドをデフォルトに**: 重み最適化よりCVオーバーフィットが少ない
2. **LBで必ず検証**: CVスコアだけで「改善した」と判断しない
3. **単体モデルも候補に**: ブレンドが必ずしも改善しない
4. **低相関モデル選択**: Spearman相関 < 0.90のモデルを優先
5. **重複検出**: OOF相関 > 0.99は同一モデルの可能性 → 除外

### S6E4での実例
- pss6e4単体: LB 0.97971
- 7モデルOptuna最適化: LB 0.97831（-0.00140）
- 3モデル均等ブレンド: LB 0.97841（-0.00130）
- 閾値最適化: LB 0.97952（-0.00019）

## 16. S6E3の知見（次コンペへの参考）
<!-- added: 2026-04-11, moved from kaggle/CLAUDE.md -->

- 7公開NB rank blending + rank_calが最強パターン
- OOF最適化(Optuna/HC/L2)はOOFは上がるがLBは変わらないことが多い
- auto_ensのような一様分布のNBは相関が低く見えるがSpearmanでは冗長
- NN(MLP)はOOF 0.914で相関0.98 → CPU学習ではブレンドに貢献しない
- Private LBフィードバック付き最適化(Late Submission)は非常に有効

## 17. サブエージェント登録基準と一覧
<!-- added: 2026-04-11, moved from kaggle/CLAUDE.md -->

### 登録するもの
- **2回以上同じ指示で使い切りエージェントを起動した場合** → 定義ファイルを作成
- **複数コンペで再利用するパターン**（パイプライン構築、モデル調査、NB生成・レビュー等）
- **レビュー系**（複数の観点から並列レビューする場合、各観点を個別エージェントに）

### 登録しないもの（使い切り）
- 1回限りの調査・検索タスク
- コンペ固有の特殊な分析（他コンペで使わない）
- 単純なファイル読み書き

### 登録済みエージェント一覧

| エージェント | 用途 | 実行タイミング |
|-------------|------|--------------|
| `pipeline-builder` | 新コンペの初期パイプライン構築 | コンペ開始時 |
| `model-researcher` | アンサンブル多様性のためのモデル調査 | OOF蓄積後 |
| `accuracy-improver` | 自律的精度改善サイクル | スコア停滞時 |
| `nb-auto-fetch-blend` | 公開NB自動取得・ブレンド | コンペ中盤以降 |
| `nb-review-readability` | NB読みやすさレビュー | NB公開前 |
| `nb-review-visualization` | NB可視化品質レビュー | NB公開前 |
| `nb-review-marketing` | NB vote獲得戦略レビュー | NB公開前 |

## 18. 無制限手法探索ルール
<!-- added: 2026-04-11, moved from kaggle/CLAUDE.md -->

### 方針
- 手法数に上限なし。効果がある限り増やし続ける
- Codex CLIで手法の実装・実行を自律的に行う
- 結果は auto_experiment.py で自動収集 → ブレンドテスト
- 改善があれば提出ファイルを自動生成

### Codex実行パターン
```bash
codex exec --full-auto --sandbox workspace-write --cd "$(pwd)" "手法リスト..."
```

### 結果管理
- scripts/exp_*.py: Codex生成スクリプト
- oof/: 各手法のOOF予測
- experiment_results_*.md: 結果レポート
- auto_experiment.py: 全OOF自動収集 → ブレンドテスト

## 19. 自律ワークフロー
<!-- added: 2026-04-11, moved from kaggle/CLAUDE.md -->

### LaunchD定期実行（トークン消費ゼロ）
| plist | 頻度 | 内容 |
|-------|------|------|
| `com.kaggle.s6e4-auto-workflow` | 毎日9/15/21時 | LB監視 → 新NB取得 → OOF自動評価 |
| `com.kaggle.playground-checker` | 毎日9時 | 新コンペ通知 |

### 自律スクリプト
| スクリプト | 用途 |
|-----------|------|
| `scripts/auto_eval.py` | OOF更新検知 → 自動評価 → ブレンド → 提出判定 |
| `scripts/fetch_new_nbs.py` | 新NB自動取得 + 相関チェック |
| `scripts/lb_monitor.py` | LBスコア監視 + macOS通知 |

### `-p` モードでの自律実行
```bash
claude -p --worktree "auto-$(date +%Y%m%d)" "nb-auto-fetch-blendエージェントを実行"
```
