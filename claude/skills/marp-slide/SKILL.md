---
name: marp-slide
description: Marp形式のプレゼンテーションスライドをMarkdownで作成・変換する
user-invocable: true
---

# Marp スライド作成スキル

Marp形式のMarkdownでプレゼンテーションスライドを作成し、PDF/PPTX/HTMLに変換する。

## 重要: 実行方式

**このスキルはMarp CLI（ローカルツール）を使用します。外部APIやクラウドサービスは使用しません。**

Marp CLIがインストールされていない場合はインストールが必要:

```bash
npm install -g @marp-team/marp-cli
# 確認
marp --version
```

## コマンド

`/marp-slide <テーマまたは指示>`

### 使用例

```
/marp-slide "Claude Codeの紹介 LT5分"
/marp-slide "四半期レポート 10枚程度"
/marp-slide --export pdf   # 既存slides.mdをPDF変換のみ
```

## ワークフロー

1. ユーザーの指示からスライド構成を決定
2. テーマCSS（このスキルの `theme.css`）を使用
3. テンプレート（`template.md`）の形式に従ってMarkdown生成
4. カレントディレクトリに `slides.md` を出力
5. `marp` コマンドでPDF/PPTXに変換

## スライド生成ルール

### 構造制約
- タイトルは最大30文字
- 1スライドあたり最大12行（箇条書き含む）
- 箇条書きは1レベルあたり最大5項目
- コードブロックは最大8行
- テーブルは最大5行×5列
- 1スライド=1つの主要メッセージ

### デザイン制約
- テーマCSSの定義済みクラスのみ使用する
- インラインスタイル（`style="..."`）は原則禁止
- HTMLの使用は最小限に抑え、Markdown構文を優先する
- 画像は `![alt](path)` で挿入、`width:` ディレクティブで制御

### Marp固有の構文
- スライド区切り: `---`
- フロントマター: `marp: true`, `theme: custom-slide`
- ディレクティブ: `<!-- _class: title -->` でスライド個別のクラス指定
- 背景画像: `![bg](image.png)`, `![bg left:40%](image.png)`
- フッター: `<!-- footer: '発表者名 | イベント名' -->`
- ページ番号: `<!-- paginate: true -->`

### 利用可能なCSSクラス（theme.css定義）

| クラス | 用途 | Markdownでの指定方法 |
|--------|------|---------------------|
| `title` | タイトルスライド | `<!-- _class: title -->` |
| `section-header` | セクション見出し | `<!-- _class: section-header -->` |
| `two-column` | 2カラムレイアウト | `<!-- _class: two-column -->` |
| `metric` | KPI・数値表示 | `<!-- _class: metric -->` |
| `code-slide` | コード中心スライド | `<!-- _class: code-slide -->` |
| `summary` | まとめスライド | `<!-- _class: summary -->` |

## 変換コマンド

```bash
# PDF変換
marp slides.md --pdf --theme ~/.claude/skills/marp-slide/theme.css --allow-local-files -o slides.pdf

# PPTX変換
marp slides.md --pptx --theme ~/.claude/skills/marp-slide/theme.css --allow-local-files -o slides.pptx

# HTML変換
marp slides.md --html --theme ~/.claude/skills/marp-slide/theme.css --allow-local-files -o slides.html
```

## エラーハンドリング

- `marp: command not found` → `npm install -g @marp-team/marp-cli` を案内
- PDF変換失敗 → `--allow-local-files` フラグの確認、Chromiumの有無を確認（`marp --chrome-path` が必要な場合あり）

## 出力

- `slides.md` — Marp形式のMarkdown（カレントディレクトリ）
- 変換後のPDF/PPTX/HTML（同ディレクトリ）
