export const meta = {
  name: 'review-deep',
  description: '多視点レビュー+反証検証。視点別発見役の指摘を反証役の多数決で確定し、誤検出を排除する',
  whenToUse: 'コード変更を高精度にレビューしたいとき。確定指摘のみが返るため誤検出の確認コストを省ける。budget指定（+300k等）で新規指摘ゼロまで探索を反復',
  phases: [
    { title: '範囲特定', detail: '対象diffと変更ファイルを収集' },
    { title: '発見', detail: '正しさ/セキュリティ/性能/回帰互換の4視点で並列探索' },
    { title: '反証検証', detail: '指摘ごとに反証役の多数決で確定' },
  ],
}

const SCOPE_SCHEMA = {
  type: 'object',
  properties: {
    files: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          path: { type: 'string' },
          change_summary: { type: 'string' },
        },
        required: ['path', 'change_summary'],
      },
    },
    diff_command: { type: 'string', description: '発見役が同じ差分を再取得するためのコマンド' },
    diff_overview: { type: 'string' },
  },
  required: ['files', 'diff_command', 'diff_overview'],
}

const FINDINGS_SCHEMA = {
  type: 'object',
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          title: { type: 'string' },
          file: { type: 'string' },
          line: { type: 'number' },
          severity: { type: 'string', enum: ['critical', 'high', 'medium', 'low'] },
          evidence: { type: 'string', description: '実際のコードを引用した根拠' },
          suggested_fix: { type: 'string' },
        },
        required: ['title', 'file', 'line', 'severity', 'evidence', 'suggested_fix'],
      },
    },
  },
  required: ['findings'],
}

const VERDICT_SCHEMA = {
  type: 'object',
  properties: {
    refuted: { type: 'boolean' },
    reasoning: { type: 'string' },
  },
  required: ['refuted', 'reasoning'],
}

const LENSES = [
  { key: 'correctness', name: '正しさ', focus: 'ロジック誤り、off-by-one、null/未定義参照、エラーハンドリング漏れ、競合状態、誤った条件分岐' },
  { key: 'security', name: 'セキュリティ', focus: 'インジェクション、機密情報のハードコードや漏洩、認証認可の欠陥、パストラバーサル、安全でないデシリアライズ' },
  { key: 'performance', name: '性能', focus: 'N+1クエリ、ループ内の不要な再計算やI/O、メモリリーク、非効率なデータ構造' },
  { key: 'regression', name: '回帰互換', focus: '既存呼び出し元の破壊、公開APIの契約変更、デフォルト挙動の変化、設定やスキーマの非互換' },
]

const REFUTER_LENSES = [
  'コードの実行パスを厳密に追跡し、指摘どおりの挙動が本当に起きるか確認する',
  '指摘の前提条件（入力・状態・タイミング）が現実に発生しうるか検証する',
  '既存のバリデーション・ガード・テスト・呼び出し文脈で既に防がれていないか確認する',
]

const a = args || {}
const refuterCount = a.refuters || 3

phase('範囲特定')
const target = a.target || 'diff'
const targetDesc = Array.isArray(target)
  ? `次のファイル群: ${target.join(', ')}（差分ではなくファイル全体をレビュー対象とする）`
  : {
      diff: '未コミットの変更全体（git diff HEAD で取得）',
      staged: 'ステージ済みの変更（git diff --cached で取得）',
      branch: 'デフォルトブランチとの差分（git merge-base でデフォルトブランチとの分岐点を特定し git diff <分岐点>...HEAD）',
      all: 'リポジトリの主要ソースコード全体',
    }[target] || target

const scope = await agent(
  `あなたはコードレビューの範囲を特定するスカウトです。カレントディレクトリのリポジトリで作業します。

レビュー対象: ${targetDesc}

タスク:
1. 対象の差分（またはファイル一覧）を取得する
2. 対象の各ファイルのパスと変更内容の一行要約をまとめる
3. 後続の発見役エージェントが同じ対象を再取得できるコマンドを diff_command に入れる（ファイル指定の場合は閲覧コマンドでよい）
4. 変更全体の概要を diff_overview にまとめる

対象が存在しない場合は files を空配列で返す。ファイルを変更しないこと。`,
  { label: 'scout:scope', schema: SCOPE_SCHEMA }
)

if (!scope || !scope.files.length) {
  return { confirmed: [], rejected_count: 0, rounds_run: 0, message: 'レビュー対象の変更が見つかりませんでした' }
}
log(`レビュー対象: ${scope.files.length}ファイル`)

const fileList = scope.files.map(f => `- ${f.path}: ${f.change_summary}`).join('\n')

const seen = new Set()
const knownTitles = []
const confirmed = []
let rejectedCount = 0
let round = 0

while (true) {
  round++
  if (a.rounds) {
    if (round > a.rounds) { round--; break }
  } else if (round > 1 && (!budget.total || budget.remaining() < 50_000)) {
    round--
    break
  }

  const exclusion = knownTitles.length
    ? `\n\n既に報告済みの指摘（再報告禁止。これら以外の新規の問題のみ探すこと）:\n${knownTitles.join('\n')}`
    : ''

  const found = (await parallel(LENSES.map(l => () =>
    agent(
      `あなたは「${l.name}」観点専門のコードレビュアーです。カレントディレクトリのリポジトリで作業します。

レビュー対象の取得コマンド: ${scope.diff_command}
対象ファイル:
${fileList}

変更概要: ${scope.diff_overview}

専門観点: ${l.focus}

タスク: 対象を取得し、必要に応じて周辺コードも読んだ上で、専門観点の問題のみを報告する。

厳守事項:
- 確証のない指摘はしない。各指摘には実際のコードを引用した evidence を必ず付ける
- スタイルや好みの問題は報告しない。実害のある問題のみ
- 1指摘につき正確な file と line を特定する
- ファイルを変更しないこと${exclusion}`,
      { label: `find:${l.key}:r${round}`, phase: '発見', schema: FINDINGS_SCHEMA }
    )
  ))).filter(Boolean).flatMap(r => r.findings)

  const fresh = found.filter(f => {
    const key = `${f.file}:${f.line}`
    if (seen.has(key)) return false
    seen.add(key)
    return true
  })
  if (!fresh.length) {
    log(`ラウンド${round}: 新規指摘なし。探索を終了します`)
    break
  }
  fresh.forEach(f => knownTitles.push(`- ${f.file}:${f.line} ${f.title}`))
  log(`ラウンド${round}: 新規指摘${fresh.length}件を反証検証にかけます`)

  const judged = (await parallel(fresh.map(f => () =>
    parallel(Array.from({ length: refuterCount }, (_, i) => () =>
      agent(
        `あなたは懐疑的なレビュー検証者です。以下のコードレビュー指摘を「反証」してください。カレントディレクトリのリポジトリで実際のコードを読んで確認します。

指摘:
- 内容: ${f.title}
- 場所: ${f.file}:${f.line}
- 深刻度: ${f.severity}
- 根拠: ${f.evidence}
- 修正案: ${f.suggested_fix}

あなたの検証観点: ${REFUTER_LENSES[i % REFUTER_LENSES.length]}

実際のコードを読んで、指摘が誤りである根拠を探すこと。指摘が正しいと確信できる場合のみ refuted=false。少しでも不確かなら refuted=true とする。ファイルを変更しないこと。`,
        { label: `refute:${f.file.split('/').pop() || f.file}:${i + 1}`, phase: '反証検証', schema: VERDICT_SCHEMA }
      )
    )).then(votes => {
      const valid = votes.filter(Boolean)
      const survives = valid.length > 0 && valid.filter(v => !v.refuted).length * 2 > valid.length
      return { ...f, survives, votes: valid.map(v => ({ refuted: v.refuted, reasoning: v.reasoning })) }
    })
  ))).filter(Boolean)

  for (const j of judged) {
    if (j.survives) confirmed.push(j)
    else rejectedCount++
  }
}

const severityRank = { critical: 0, high: 1, medium: 2, low: 3 }
confirmed.sort((x, y) => (severityRank[x.severity] ?? 9) - (severityRank[y.severity] ?? 9))

return {
  confirmed: confirmed.map(f => ({
    title: f.title,
    file: f.file,
    line: f.line,
    severity: f.severity,
    evidence: f.evidence,
    suggested_fix: f.suggested_fix,
  })),
  rejected_count: rejectedCount,
  rounds_run: round,
  files_reviewed: scope.files.length,
}
