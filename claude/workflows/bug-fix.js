export const meta = {
  name: 'bug-fix',
  description: '再現ファーストのバグ修正。失敗する再現テスト→仮説の並列検証→修正→対症療法チェックまで構造化して実行する',
  whenToUse: 'バグ報告を根本原因から直したいとき。args.bug にバグの説明が必須。再現できない場合は修正せず不足情報を報告する',
  phases: [
    { title: '再現', detail: '失敗する再現テストを作成して失敗を確認' },
    { title: '仮説生成', detail: '4視点で原因仮説を並列生成' },
    { title: '仮説検証', detail: '上位仮説をコード読解で支持/棄却' },
    { title: '修正', detail: '根本原因を修正し再現テスト+全テスト+lintで確認' },
    { title: '最終検証', detail: '対症療法でないか独立検証' },
  ],
}

const REPRO_SCHEMA = {
  type: 'object',
  properties: {
    reproduced: { type: 'boolean' },
    repro_path: { type: 'string', description: '再現テストのパス（再現失敗時は空文字）' },
    repro_command: { type: 'string', description: '再現テストだけを実行するコマンド' },
    fail_output: { type: 'string', description: '失敗時の出力の要点' },
    missing_info: { type: 'string', description: '再現できない場合に不足している情報' },
  },
  required: ['reproduced', 'repro_path', 'repro_command', 'fail_output', 'missing_info'],
}

const HYPOTHESES_SCHEMA = {
  type: 'object',
  properties: {
    hypotheses: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          cause: { type: 'string' },
          location: { type: 'string', description: '原因と推測する file:line または関数名' },
          confidence: { type: 'number', description: '確信度 1-10' },
          how_to_check: { type: 'string' },
        },
        required: ['cause', 'location', 'confidence', 'how_to_check'],
      },
    },
  },
  required: ['hypotheses'],
}

const INVESTIGATION_SCHEMA = {
  type: 'object',
  properties: {
    supported: { type: 'boolean' },
    evidence: { type: 'string' },
    root_cause_detail: { type: 'string', description: '支持される場合、根本原因の詳細な説明' },
  },
  required: ['supported', 'evidence', 'root_cause_detail'],
}

const FIX_SCHEMA = {
  type: 'object',
  properties: {
    fixed: { type: 'boolean', description: '再現テスト+全テスト+lintが全て通過したらtrue' },
    changes: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          file: { type: 'string' },
          summary: { type: 'string' },
        },
        required: ['file', 'summary'],
      },
    },
    test_output: { type: 'string' },
    failure_reason: { type: 'string', description: '失敗時の原因。成功時は空文字' },
  },
  required: ['fixed', 'changes', 'test_output', 'failure_reason'],
}

const SYMPTOM_CHECK_SCHEMA = {
  type: 'object',
  properties: {
    is_root_cause_fix: { type: 'boolean' },
    reasoning: { type: 'string' },
    concerns: { type: 'array', items: { type: 'string' } },
  },
  required: ['is_root_cause_fix', 'reasoning', 'concerns'],
}

const a = args || {}
if (!a.bug) {
  return { status: '引数エラー', message: 'args.bug にバグの説明を渡してください。例: Workflow({name:"bug-fix"}, {bug:"ログイン後に500エラー", repro_hint:"..."})' }
}
const verifyCmd = a.verify_cmd || 'プロジェクト構成から自動判定（pytest+ruff / npm test+eslint+tsc など）'

phase('再現')
const repro = await agent(
  `あなたはバグ再現の専門家です。カレントディレクトリのリポジトリで作業します。

バグ報告: ${a.bug}
${a.repro_hint ? `再現のヒント: ${a.repro_hint}` : ''}

タスク:
1. プロジェクトのテスト規約を確認する（テストの配置場所・フレームワーク・命名）
2. このバグを最小限に再現する「失敗するテスト」を作成する（例: tests/test_repro_<短い名前>.py）
3. テストを実行し、バグが原因で失敗することを確認する（テスト自体の不備による失敗ではないこと）
4. 再現テストだけを実行するコマンドを repro_command に入れる

厳守事項:
- 再現テスト以外のファイルを変更しないこと（実装コード・既存テストは触らない）
- 誠実に試みても再現できない場合は reproduced=false とし、何が不足しているか（環境・データ・手順）を missing_info に具体的に書く。無理に「再現した」ことにしない`,
  { label: 'repro', schema: REPRO_SCHEMA }
)

if (!repro || !repro.reproduced) {
  return {
    status: '再現失敗',
    missing_info: repro ? repro.missing_info : '再現エージェントが応答しませんでした',
    detail: repro ? repro.fail_output : '',
    next_step: '不足情報を repro_hint に補って再実行してください。再現なしでの修正は対症療法のリスクが高いため行いません',
  }
}
log(`再現成功: ${repro.repro_path}`)

phase('仮説生成')
const HYPO_LENSES = [
  { key: 'logic', name: 'ロジック誤り', focus: '条件分岐の誤り、計算ミス、誤ったアルゴリズム、制御フローの問題' },
  { key: 'state', name: 'データ・状態管理', focus: '不正なデータ、状態の不整合、キャッシュ、永続化、初期化漏れ' },
  { key: 'boundary', name: '境界条件・型', focus: 'null/空/ゼロ/最大値、型の不一致、暗黙の変換、エンコーディング' },
  { key: 'env', name: '環境・依存・並行性', focus: '依存ライブラリ、設定、環境差異、タイミング、並行アクセス' },
]
const hypoResults = await parallel(HYPO_LENSES.map(l => () =>
  agent(
    `あなたは「${l.name}」観点のバグ原因分析者です。カレントディレクトリのリポジトリを読んで分析します（ファイル変更禁止）。

バグ報告: ${a.bug}
再現テスト: ${repro.repro_path}（実行コマンド: ${repro.repro_command}）
失敗時の出力: ${repro.fail_output}

専門観点: ${l.focus}

タスク: 再現テストと関連コードを読み、この観点での原因仮説を最大3件挙げる。各仮説には原因箇所（file:lineまたは関数名）、確信度1-10、確認方法を付ける。この観点で可能性が低ければ無理に挙げず空配列でよい。`,
    { label: `hypo:${l.key}`, phase: '仮説生成', agentType: 'Explore', schema: HYPOTHESES_SCHEMA }
  )
))
const allHypotheses = hypoResults.filter(Boolean).flatMap(r => r.hypotheses)
if (!allHypotheses.length) {
  return { status: '原因特定失敗', repro_test: repro.repro_path, next_step: '仮説が得られませんでした。バグ説明を詳細化して再実行してください' }
}

const ranked = allHypotheses.slice().sort((x, y) => y.confidence - x.confidence)
const top = []
const seenLocations = new Set()
for (const h of ranked) {
  if (seenLocations.has(h.location)) continue
  seenLocations.add(h.location)
  top.push(h)
  if (top.length >= 4) break
}
log(`仮説${allHypotheses.length}件から上位${top.length}件を検証します`)

phase('仮説検証')
const investigations = (await parallel(top.map((h, i) => () =>
  agent(
    `あなたはバグ原因仮説の検証者です。カレントディレクトリのリポジトリを読んで検証します（ファイル変更禁止）。

バグ報告: ${a.bug}
再現テスト実行コマンド: ${repro.repro_command}
失敗時の出力: ${repro.fail_output}

検証する仮説:
- 原因: ${h.cause}
- 箇所: ${h.location}
- 確認方法: ${h.how_to_check}

タスク: 関連コードを精読し、必要なら再現テストや確認用コマンドを実行して、この仮説が実際の失敗を説明できるか判定する。コードの実行パスを具体的に追跡し、evidence には実際のコードと観察結果を引用する。説明できない・別の原因が濃厚な場合は supported=false。`,
    { label: `verify:hypo${i + 1}`, phase: '仮説検証', agentType: 'Explore', schema: INVESTIGATION_SCHEMA }
  ).then(v => v && ({ ...h, ...v }))
))).filter(Boolean)

const supported = investigations.filter(v => v.supported)
if (!supported.length) {
  return {
    status: '原因特定失敗',
    repro_test: repro.repro_path,
    investigated: investigations.map(v => ({ cause: v.cause, location: v.location, evidence: v.evidence })),
    next_step: '全仮説が棄却されました。検証結果を参考に追加情報を与えて再実行してください',
  }
}
const rootCause = supported[0]
log(`根本原因を特定: ${rootCause.location}`)

phase('修正')
let fixResult = null
const failureHistory = []
for (let attempt = 1; attempt <= 6; attempt++) {
  const differentApproach = attempt > 3
    ? '\n\n重要: これまでの修正アプローチは3回失敗しています。前提を疑い、これまでと根本的に異なるアプローチを取ってください。'
    : ''
  const history = failureHistory.length
    ? `\n\n過去の失敗:\n${failureHistory.map((f, i) => `試行${i + 1}: ${f}`).join('\n')}`
    : ''
  fixResult = await agent(
    `あなたはバグ修正の実装者です。カレントディレクトリのリポジトリで作業します。

バグ報告: ${a.bug}
根本原因: ${rootCause.cause}（箇所: ${rootCause.location}）
根拠: ${rootCause.root_cause_detail}
${rootCause.evidence}

再現テスト: ${repro.repro_path}（実行コマンド: ${repro.repro_command}）
検証コマンド: ${verifyCmd}

タスク:
1. 根本原因を修正する（症状を隠す対症療法は禁止）
2. 再現テストが通過することを確認する
3. 既存テスト全体と lint を実行し、全て通過することを確認する
4. 全て通過した場合のみ fixed=true

厳守事項:
- 既存テストおよび再現テストの期待値を変更しないこと。テスト失敗は実装側で解決する
- 修正範囲は最小限に。関連する改善案は changes の summary に TODO として記すだけにする${differentApproach}${history}`,
    { label: `fix:attempt${attempt}`, phase: '修正', schema: FIX_SCHEMA }
  )
  if (fixResult && fixResult.fixed) break
  failureHistory.push(fixResult ? fixResult.failure_reason : 'エージェントが応答しませんでした')
  log(`修正試行${attempt}が失敗${attempt === 3 ? '。次の試行から異なるアプローチに切り替えます' : ''}`)
}

if (!fixResult || !fixResult.fixed) {
  return {
    status: '修正失敗',
    todo: `TODO(autonomous): ${a.bug} — 6回の修正試行が失敗。根本原因候補: ${rootCause.cause}（${rootCause.location}）`,
    root_cause: { cause: rootCause.cause, location: rootCause.location },
    repro_test: repro.repro_path,
    attempts: failureHistory,
  }
}

phase('最終検証')
const check = await agent(
  `あなたは懐疑的な修正検証者です。カレントディレクトリのリポジトリで、適用済みのバグ修正が「対症療法ではないか」を反証視点で検証します（ファイル変更禁止）。

バグ報告: ${a.bug}
特定された根本原因: ${rootCause.cause}（${rootCause.location}）
修正内容:
${fixResult.changes.map(c => `- ${c.file}: ${c.summary}`).join('\n')}

タスク:
1. git diff で実際の修正を確認する
2. 修正が根本原因に対処しているか、それとも症状（エラー表示・特定入力のみ）を握りつぶしているだけかを判定する
3. 同じ原因が他の箇所にも潜んでいないか確認し、あれば concerns に挙げる
4. 再現テスト（${repro.repro_command}）が通過することを再確認する

疑わしい点があれば is_root_cause_fix=false とし、理由を具体的に書く。`,
  { label: 'symptom-check', schema: SYMPTOM_CHECK_SCHEMA }
)

return {
  status: '完了',
  root_cause: { cause: rootCause.cause, location: rootCause.location, detail: rootCause.root_cause_detail },
  fix_summary: fixResult.changes,
  repro_test: repro.repro_path,
  verified: fixResult.fixed,
  root_cause_fix_check: check
    ? { is_root_cause_fix: check.is_root_cause_fix, reasoning: check.reasoning, concerns: check.concerns }
    : { is_root_cause_fix: false, reasoning: '検証エージェントが応答しませんでした', concerns: [] },
}
