export const meta = {
  name: 'refactor-migrate',
  description: '全件変換+完全性検証。多モード走査で対象を洗い出し、ファイル単位で並列変換し、取りこぼしゼロまで反復する',
  whenToUse: 'API置換・パターン移行・一括リネームなど機械的な全件変更。args.instruction に変換内容が必須',
  phases: [
    { title: '探索', detail: '多モード走査で対象箇所を洗い出しファイル単位に分配' },
    { title: '変換', detail: 'ファイルグループごとに並列変換' },
    { title: '検証', detail: 'テスト+完全性批評（取りこぼし再走査）' },
  ],
}

const SITES_SCHEMA = {
  type: 'object',
  properties: {
    sites: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          file: { type: 'string' },
          line: { type: 'number' },
          snippet: { type: 'string' },
          note: { type: 'string' },
        },
        required: ['file', 'line', 'snippet', 'note'],
      },
    },
  },
  required: ['sites'],
}

const TRANSFORM_SCHEMA = {
  type: 'object',
  properties: {
    changed: { type: 'boolean' },
    summary: { type: 'string' },
    skipped: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          site: { type: 'string' },
          reason: { type: 'string' },
        },
        required: ['site', 'reason'],
      },
      description: '変換すべきでないと判断してスキップした箇所',
    },
  },
  required: ['changed', 'summary', 'skipped'],
}

const VERIFY_SCHEMA = {
  type: 'object',
  properties: {
    passing: { type: 'boolean', description: 'テスト・lint・型チェックが全て通過したらtrue' },
    output: { type: 'string', description: '実行結果の要点' },
    repairs_made: { type: 'string', description: '変換起因の失敗を修復した場合その内容。なければ空文字' },
  },
  required: ['passing', 'output', 'repairs_made'],
}

const a = args || {}
if (!a.instruction) {
  return { status: '引数エラー', message: 'args.instruction に変換内容を渡してください。例: Workflow({name:"refactor-migrate"}, {instruction:"requests を httpx に置換", pattern:"requests"})' }
}
const verifyCmd = a.verify_cmd || 'プロジェクト構成から自動判定（pytest+ruff / npm test+eslint+tsc など）'
const scopeNote = a.paths && a.paths.length ? `\n探索範囲: ${a.paths.join(', ')} 配下に限定する` : ''

const SCOUT_MODES = [
  { key: 'name', desc: '識別子・シンボル名・ファイル名での直接的なgrep検索' },
  { key: 'content', desc: 'パターンの意味的な変種（エイリアス、ラッパー関数、文字列リテラル内の参照、設定ファイル・ドキュメント内の言及）の検索' },
  { key: 'usage', desc: 'import/require/呼び出し関係をたどり、間接的に影響を受ける箇所の特定' },
]

const groupByFile = (sites) => {
  const groups = {}
  for (const s of sites) {
    if (!groups[s.file]) groups[s.file] = []
    groups[s.file].push(s)
  }
  return Object.entries(groups).map(([file, fileSites]) => ({ file, sites: fileSites }))
}

phase('探索')
const scoutResults = await parallel(SCOUT_MODES.map(m => () =>
  agent(
    `あなたはコード変換対象の探索者です。カレントディレクトリのリポジトリを走査します（ファイル変更禁止）。

変換内容: ${a.instruction}
${a.pattern ? `手がかりパターン: ${a.pattern}` : ''}${scopeNote}

あなたの走査モード: ${m.desc}

タスク: このモードで変換対象となる箇所を全て洗い出す。各箇所に file・line・該当コードの snippet・変換時の注意点 note を付ける。対象でない可能性が高い箇所は含めない。`,
    { label: `scout:${m.key}`, phase: '探索', agentType: 'Explore', schema: SITES_SCHEMA }
  )
))

const seenKeys = new Set()
const dedupFresh = (sites) => sites.filter(s => {
  const key = `${s.file}:${s.line}`
  if (seenKeys.has(key)) return false
  seenKeys.add(key)
  return true
})

const initialSites = dedupFresh(scoutResults.filter(Boolean).flatMap(r => r.sites))
if (!initialSites.length) {
  return { status: '対象なし', message: '変換対象が見つかりませんでした。pattern や paths の指定を確認してください' }
}

let currentGroups = groupByFile(initialSites)
log(`変換対象: ${initialSites.length}箇所 / ${currentGroups.length}ファイル`)

let totalChanged = 0
const allSkipped = []
let round = 0
let suiteResult = null
let remainingGroups = []

while (currentGroups.length) {
  round++
  if (round > 3) {
    remainingGroups = currentGroups
    break
  }

  const transforms = (await parallel(currentGroups.map(g => () =>
    agent(
      `あなたはコード変換の実装者です。カレントディレクトリのリポジトリで作業します。

変換内容: ${a.instruction}

担当ファイル: ${g.file}
対象箇所:
${g.sites.map(s => `- L${s.line}: ${s.snippet}（${s.note}）`).join('\n')}

厳守事項:
- 担当ファイル以外は変更しないこと（他のファイルは並列で別エージェントが担当している）
- 変換の意図を保ち、挙動を変えないこと。リスト外でも同一ファイル内の同種箇所は変換してよい
- 変換すべきでないと判断した箇所は無理に変えず skipped に理由付きで報告する
- 既存テストを変更しないこと`,
      { label: `transform:${g.file.split('/').pop() || g.file}`, phase: '変換', schema: TRANSFORM_SCHEMA }
    )
  ))).filter(Boolean)
  totalChanged += transforms.filter(t => t.changed).length
  for (const t of transforms) allSkipped.push(...t.skipped)

  const [suite, missed] = await parallel([
    () => agent(
      `あなたは変換後の検証者です。カレントディレクトリのリポジトリで作業します。

直前に「${a.instruction}」の一括変換が行われました。

タスク:
1. 検証コマンドを実行する: ${verifyCmd}
2. 失敗があれば変換起因かを判断し、変換起因なら修復する（変換の意図は保つこと。既存テストの変更は禁止）
3. 修復後に再実行し、最終結果を報告する。変換と無関係の既存の失敗は repairs_made に「変換と無関係」と明記して passing の判断から除外してよい`,
      { label: `verify:r${round}`, phase: '検証', schema: VERIFY_SCHEMA }
    ),
    () => agent(
      `あなたは変換の完全性批評者です。カレントディレクトリのリポジトリを走査します（ファイル変更禁止）。

変換内容: ${a.instruction}
${a.pattern ? `手がかりパターン: ${a.pattern}` : ''}${scopeNote}

タスク: 変換の「取りこぼし」を探す。grepの表記揺れ・別名・文字列内参照・設定ファイル・ドキュメントも含めて再走査し、まだ変換されていない箇所のみを報告する。変換済みの箇所は含めない。見つからなければ空配列を返す。`,
      { label: `critic:r${round}`, phase: '検証', agentType: 'Explore', schema: SITES_SCHEMA }
    ),
  ])
  suiteResult = suite

  if (suite && !suite.passing) {
    return {
      status: '検証失敗',
      sites_changed: totalChanged,
      rounds: round,
      verify_output: suite.output,
      skipped: allSkipped,
      next_step: 'テストが通過しない状態です。verify_output を確認して手動対応するか、bug-fix ワークフローに引き継いでください',
    }
  }

  const freshSites = dedupFresh(missed ? missed.sites : [])
  if (!freshSites.length) {
    log(`ラウンド${round}: 取りこぼしなし。完了`)
    break
  }
  currentGroups = groupByFile(freshSites)
  log(`ラウンド${round}: 取りこぼし${freshSites.length}箇所を追加変換します`)
}

return {
  status: remainingGroups.length ? '一部残件あり' : '完了',
  sites_found: seenKeys.size,
  sites_changed_files: totalChanged,
  rounds: round,
  skipped: allSkipped,
  remaining_todos: remainingGroups.flatMap(g => g.sites.map(s => `TODO: ${s.file}:${s.line} ${s.snippet}`)),
  verify: suiteResult ? { passing: suiteResult.passing, repairs_made: suiteResult.repairs_made } : null,
}
