export const meta = {
  name: 'codebase-map',
  description: 'コードベース理解マップ。サブシステム別の並列リーダーで読み込み、完全性批評を経て構造化マップを生成する',
  whenToUse: '新規プロジェクト参画時、大きな変更の前、app-devハーネスの理解フェーズ。args.focus で関心領域を絞れる',
  phases: [
    { title: '区分', detail: '構造を把握しサブシステムに分割' },
    { title: '読込', detail: 'サブシステム別リーダーが並列で精読' },
    { title: '統合', detail: 'マップ生成+完全性批評（未踏領域の追加読込）' },
  ],
}

const PARTITION_SCHEMA = {
  type: 'object',
  properties: {
    project_summary: { type: 'string', description: 'プロジェクトの目的と技術スタックの要約' },
    subsystems: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          name: { type: 'string' },
          paths: { type: 'array', items: { type: 'string' } },
          hint: { type: 'string', description: 'リーダーへの読み方のヒント' },
        },
        required: ['name', 'paths', 'hint'],
      },
    },
  },
  required: ['project_summary', 'subsystems'],
}

const SUBSYSTEM_SCHEMA = {
  type: 'object',
  properties: {
    purpose: { type: 'string' },
    key_files: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          path: { type: 'string' },
          role: { type: 'string' },
        },
        required: ['path', 'role'],
      },
    },
    entry_points: { type: 'array', items: { type: 'string' } },
    interfaces: { type: 'array', items: { type: 'string' }, description: '他サブシステムに公開しているAPI・契約' },
    dependencies: { type: 'array', items: { type: 'string' }, description: '依存する他サブシステム・外部サービス' },
    risks: { type: 'array', items: { type: 'string' }, description: '変更時に壊しやすい箇所・暗黙の前提' },
    conventions: { type: 'array', items: { type: 'string' }, description: 'このサブシステム特有の規約・パターン' },
  },
  required: ['purpose', 'key_files', 'entry_points', 'interfaces', 'dependencies', 'risks', 'conventions'],
}

const GAPS_SCHEMA = {
  type: 'object',
  properties: {
    complete: { type: 'boolean' },
    gaps: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          name: { type: 'string' },
          paths: { type: 'array', items: { type: 'string' } },
          hint: { type: 'string' },
        },
        required: ['name', 'paths', 'hint'],
      },
    },
  },
  required: ['complete', 'gaps'],
}

const a = args || {}
const depth = a.depth || 'overview'
const maxSubsystems = depth === 'deep' ? 12 : 8
const focusNote = a.focus ? `\n特に注目する領域: ${a.focus}` : ''

phase('区分')
const partition = await agent(
  `あなたはコードベース調査の設計者です。カレントディレクトリのリポジトリを調査します（ファイル変更禁止）。
${focusNote}
タスク:
1. ディレクトリ構造・README・設定ファイルからプロジェクトの目的と技術スタックを把握する
2. コードベースを意味のあるサブシステム（責務のまとまり）に分割する。最大${maxSubsystems}個
3. 各サブシステムに対象パスと「読み方のヒント」（何に注目すべきか）を付ける

ディレクトリ構造をそのまま写すのではなく、責務の単位で分割すること。テスト・CI設定なども重要なら1サブシステムとして扱ってよい。`,
  { label: 'partition', agentType: 'Explore', schema: PARTITION_SCHEMA }
)

if (!partition || !partition.subsystems.length) {
  return { status: '失敗', message: 'コードベースの構造を把握できませんでした' }
}
const subsystems = partition.subsystems.slice(0, maxSubsystems)
if (partition.subsystems.length > maxSubsystems) {
  log(`サブシステム${partition.subsystems.length}個のうち先頭${maxSubsystems}個のみ読込（depth:'deep' で拡大可）`)
}
log(`${subsystems.length}サブシステムを並列読込します`)

const readOne = (s, phaseTitle) =>
  agent(
    `あなたはサブシステム「${s.name}」の専属リーダーです。カレントディレクトリのリポジトリを読みます（ファイル変更禁止）。

プロジェクト概要: ${partition.project_summary}${focusNote}

担当: ${s.name}
対象パス: ${s.paths.join(', ')}
読み方のヒント: ${s.hint}

タスク: 対象を${depth === 'deep' ? '精読（主要ファイルは全文）' : '通読（構造とインターフェース中心）'}し、目的・主要ファイルと役割・エントリポイント・公開インターフェース・依存・変更時のリスク・特有の規約をまとめる。推測で書かず、実際に読んだ内容のみ報告する。`,
    { label: `read:${s.name.slice(0, 24)}`, phase: phaseTitle, agentType: 'Explore', schema: SUBSYSTEM_SCHEMA }
  ).then(r => r && ({ name: s.name, paths: s.paths, ...r }))

phase('読込')
let readings = (await parallel(subsystems.map(s => () => readOne(s, '読込')))).filter(Boolean)
if (!readings.length) {
  return { status: '失敗', message: 'サブシステムの読込に全て失敗しました' }
}

phase('統合')
const readingsText = readings.map(r =>
  `### ${r.name}（${r.paths.join(', ')}）
目的: ${r.purpose}
主要ファイル: ${r.key_files.map(f => `${f.path}=${f.role}`).join(' / ')}
エントリポイント: ${r.entry_points.join(', ')}
インターフェース: ${r.interfaces.join(' / ')}
依存: ${r.dependencies.join(', ')}
リスク: ${r.risks.join(' / ')}
規約: ${r.conventions.join(' / ')}`
).join('\n\n')

const critic = await agent(
  `あなたはコードベース調査の完全性批評者です。カレントディレクトリのリポジトリを確認します（ファイル変更禁止）。

これまでの調査結果:
プロジェクト概要: ${partition.project_summary}

調査済みサブシステム:
${readingsText}

タスク: リポジトリ全体を見渡し、調査から漏れている重要な領域（未調査のディレクトリ、説明されていない依存先、調査が薄い重要箇所）を gaps として挙げる。漏れがなければ complete=true。些細な漏れ（生成物・vendorディレクトリ等）は挙げない。最大4件。`,
  { label: 'critic', phase: '統合', agentType: 'Explore', schema: GAPS_SCHEMA }
)

if (critic && !critic.complete && critic.gaps.length) {
  log(`未踏領域${critic.gaps.length}件を追加読込します`)
  const extra = (await parallel(critic.gaps.slice(0, 4).map(g => () => readOne(g, '統合')))).filter(Boolean)
  readings = readings.concat(extra)
}

const finalReadingsText = readings.map(r =>
  `### ${r.name}（${r.paths.join(', ')}）
目的: ${r.purpose}
主要ファイル: ${r.key_files.map(f => `${f.path}=${f.role}`).join(' / ')}
エントリポイント: ${r.entry_points.join(', ')}
インターフェース: ${r.interfaces.join(' / ')}
依存: ${r.dependencies.join(', ')}
リスク: ${r.risks.join(' / ')}
規約: ${r.conventions.join(' / ')}`
).join('\n\n')

const mapMd = await agent(
  `あなたはコードベースマップの編集者です。以下の調査結果を1つの読みやすいMarkdownマップに統合してください。

プロジェクト概要: ${partition.project_summary}${focusNote}

調査結果:
${finalReadingsText}

構成: # コードベースマップ / ## プロジェクト概要 / ## アーキテクチャ全体像（サブシステム間の依存関係を文章+箇条書きで） / ## サブシステム詳細（各サブシステムごとに目的・主要ファイル・インターフェース・リスク） / ## 横断的な規約 / ## 変更時の注意点（リスクの統合）。

${a.out ? `完成したマップを ${a.out} にファイルとして保存し、保存先パスを含めて` : 'ファイルは作成せず、'}マップ全文をそのまま返答として返すこと。`,
  { label: 'synthesize', phase: '統合' }
)

return {
  status: '完了',
  subsystems_read: readings.length,
  gaps_filled: critic && critic.gaps ? Math.min(critic.gaps.length, 4) : 0,
  out: a.out || null,
  map_md: mapMd || '統合エージェントが応答しませんでした',
}
