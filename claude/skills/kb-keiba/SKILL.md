---
name: kb-keiba
description: 競馬予測プロジェクトのドメイン知識ベース。ML戦略・スクレイピング・データ収集・EVフィルタの知見を蓄積
user-invocable: true
---

# 競馬予測ナレッジベース

## ML戦略（確定）

### 本番戦略
- **モデル**: LGBM-NoOdds（オッズ特徴量を除外したLightGBM LambdaRank）
- **ベット**: 複勝EVフィルタ（EV > 0.2, softmax temp = 1.0）
- **実績**: ROI = 1.97（12F平均）、的中率100%
- **ベット頻度**: 月4-6回

### なぜLGBM-NoOddsか
- オッズを使わないことで市場と独立したエッジを生成
- オッズ依存モデル（LambdaMART等）より複勝ROIが高い
- 理由: オッズは既に市場参加者の予測を反映→独自エッジが小さい

### EVフィルタの仕組み
```
P_place = min(softmax_prob × 3.0, 1.0)  # 従来近似
EV = P_place × odds_place - 1.0
EV > 0.2 → ベット推薦
```
改善版: PlaceCalibrator（isotonic regression）でP_placeを校正

### 最適パラメータ（グリッドサーチ済み）
| パラメータ | 最適値 | 根拠 |
|-----------|--------|------|
| softmax temp | 1.0 | 0.5は賭けすぎ、2.0は少なすぎ |
| EV閾値 | 0.2 | 0.15-0.25で安定、0.2がバランス型 |
| Kelly fraction | 0.25 | フルKellyは禁止 |
| max_bet_pct | 0.01 | 1ベット資金1% |
| max_daily_pct | 0.03 | 日次損失3% |

## スクレイピングの鉄則

- **最大4ワーカー**（5以上は確実にブロック）
- **間隔**: 1ワーカー5-10秒、4ワーカー3-6秒
- **adaptive=false** が安定
- **ブロック後24時間待機**（数時間では復旧しない）
- **verbose禁止**（ログ25-30GB膨張）
- **Playwright必須**（2024年11月以降のnetkeiba対策）
- **robotパターン誤検知に注意**（AI予想セクションのrobot画像URL）
- **日付パース**: kaisai_dateパラメータ + dd.Activeから抽出

## データ収集実績

- DB: 63,949レース（2007-07〜2026-03）
- 安定構成: 2グループ×2ワーカー（2.5日間安定、6600件、ブロック0）
- odds_placeバックフィル: 結果ページ払戻テーブルから取得（3着以内馬のみ）

## 検証方法

- 12Fウォークフォワード: train=1095日, test=90日, step=90日
- 指標: NDCG@1, WinRate, PlaceRate, ROI_win, ROI_place, Composite
- EVフィルタ指標: filtered_roi_place, filtered_place_bet_count, filtered_place_rate
- キャリブレーション指標: Brier score, ECE

## モデル管理

- 保存: ml/saved_models/v{version}_{timestamp}/
- latest: シンボリックリンクで最新を指す
- registry: ModelRegistry（DB管理、deploy/archive/rollback）
- 再学習: 週次月曜01:00（drift検知→retrain→A/B昇格）

## 税務の注意点

- 公営競技払戻金: 一時所得（50万円控除+50%課税）
- 継続的・機械的購入: 雑所得論点あり→税理士確認推奨
- ROI 1.2以上でないと税引後プラスにならない可能性
