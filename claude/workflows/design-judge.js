export const meta = {
  name: 'design-judge',
  description: '設計ジャッジパネル。異なる観点でN案を独立生成し、審査員パネルの採点で勝者を決め、次点の良い部分を移植して統合する',
  whenToUse: '設計判断の質を上げたいとき（アーキテクチャ選定、機能設計、技術選定）。args.problem に課題が必須',
  phases: [
    { title: '文脈収集', detail: '関連コードの制約を要約（context_paths指定時のみ）' },
    { title: '設計生成', detail: '観点別の設計者が独立にN案を生成' },
    { title: '審査', detail: '審査員パネルが4軸で全案を採点' },
    { title: '統合', detail: '勝者ベース+次点の良い部分を移植した最終設計書を合成' },
  ],
}

const CONTEXT_SCHEMA = {
  type: 'object',
  properties: {
    brief: { type: 'string', description: '設計に影響する既存コードの要点' },
    constraints: { type: 'array', items: { type: 'string' } },
  },
  required: ['brief', 'constraints'],
}

const DESIGN_SCHEMA = {
  type: 'object',
  properties: {
    summary: { type: 'string', description: '設計の一段落要約' },
    components: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          name: { type: 'string' },
          responsibility: { type: 'string' },
        },
        required: ['name', 'responsibility'],
      },
    },
    key_decisions: { type: 'array', items: { type: 'string' } },
    tradeoffs: { type: 'array', items: { type: 'string' } },
    risks: { type: 'array', items: { type: 'string' } },
  },
  required: ['summary', 'components', 'key_decisions', 'tradeoffs', 'risks'],
}

const SCORE_SCHEMA = {
  type: 'object',
  properties: {
    scores: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          candidate: { type: 'number', description: '候補番号' },
          feasibility: { type: 'number', description: '実現可能性 1-10' },
          extensibility: { type: 'number', description: '拡張性 1-10' },
          risk_management: { type: 'number', description: 'リスクの低さ 1-10' },
          simplicity: { type: 'number', description: 'シンプルさ 1-10' },
          total: { type: 'number', description: '4軸の合計' },
          rationale: { type: 'string' },
        },
        required: ['candidate', 'feasibility', 'extensibility', 'risk_management', 'simplicity', 'total', 'rationale'],
      },
    },
  },
  required: ['scores'],
}

const JUDGE_LENSES = [
  '実装者視点: 作る難しさ、工数、技術的リスク、チームの実装能力との適合',
  '運用・保守視点: 障害時の調査しやすさ、変更容易性、監視・デバッグのしやすさ',
  'ユーザー価値視点: 要求の充足度、体験の質、提供までの速さ、優先順位の正しさ',
]

const a = args || {}
if (!a.problem) {
  return { status: '引数エラー', message: 'args.problem に設計課題を渡してください。例: Workflow({name:"design-judge"}, {problem:"通知システムの設計", context_paths:["src/notifications/"]})' }
}
const perspectives = a.perspectives || [
  'MVP優先: 最小で動くものを最速で出すことを最重視する',
  'リスク優先: 失敗モード・セキュリティ・データ整合性を最重視する',
  '拡張性優先: 将来の変更容易性と機能追加のしやすさを最重視する',
]
const judgeCount = a.judges || 3

phase('文脈収集')
let contextBrief = ''
if (a.context_paths && a.context_paths.length) {
  const ctx = await agent(
    `あなたは設計の前提調査者です。カレントディレクトリのリポジトリを読みます（ファイル変更禁止）。

設計課題: ${a.problem}
調査対象: ${a.context_paths.join(', ')}

タスク: 対象を読み、この設計課題に影響する既存コードの構造・規約・技術スタックを brief に、設計が従うべき制約を constraints にまとめる。`,
    { label: 'context', agentType: 'Explore', schema: CONTEXT_SCHEMA }
  )
  if (ctx) {
    contextBrief = `\n\n既存コードの文脈:\n${ctx.brief}\n\n制約:\n${ctx.constraints.map(c => `- ${c}`).join('\n')}`
  }
}

phase('設計生成')
const candidates = (await parallel(perspectives.map((p, i) => () =>
  agent(
    `あなたは独立した設計者です。他の設計者の案は見えません。あなた自身の最良の設計を出してください。

設計課題: ${a.problem}${contextBrief}

あなたの設計観点: ${p}

タスク: この観点を最重視した設計を作る。構成要素と責務、重要な設計判断、トレードオフ、リスクを明示する。観点に忠実であること（バランスを取ろうとしない。それは後段の統合者の仕事）。必要ならリポジトリのコードを読んで構わないが、ファイルは変更しないこと。`,
    { label: `design:${i + 1}`, phase: '設計生成', schema: DESIGN_SCHEMA }
  ).then(d => d && ({ index: i + 1, perspective: p, ...d }))
))).filter(Boolean)

if (candidates.length < 2) {
  return { status: '生成失敗', message: `設計候補が${candidates.length}案しか得られませんでした。再実行してください` }
}
log(`設計${candidates.length}案を生成。審査員${judgeCount}名で採点します`)

const candidatesText = candidates.map(c =>
  `### 候補${c.index}（観点: ${c.perspective}）
要約: ${c.summary}
構成: ${c.components.map(x => `${x.name}=${x.responsibility}`).join(' / ')}
設計判断: ${c.key_decisions.join(' / ')}
トレードオフ: ${c.tradeoffs.join(' / ')}
リスク: ${c.risks.join(' / ')}`
).join('\n\n')

phase('審査')
const judgeResults = (await parallel(Array.from({ length: judgeCount }, (_, j) => () =>
  agent(
    `あなたは設計審査員です。以下の設計課題に対する全候補を採点してください。

設計課題: ${a.problem}${contextBrief}

あなたの審査視点: ${JUDGE_LENSES[j % JUDGE_LENSES.length]}

候補一覧:
${candidatesText}

タスク: 各候補を4軸（実現可能性・拡張性・リスクの低さ・シンプルさ）で1-10点採点する。あなたの審査視点を重視しつつ、根拠を rationale に書く。全候補に同じ点を付けず、差を明確にすること。`,
    { label: `judge:${j + 1}`, phase: '審査', schema: SCORE_SCHEMA }
  )
))).filter(Boolean)

if (!judgeResults.length) {
  return { status: '審査失敗', candidates: candidates.map(c => ({ index: c.index, perspective: c.perspective, summary: c.summary })) }
}

const totals = candidates.map(c => ({ index: c.index, perspective: c.perspective, sum: 0, count: 0 }))
for (const jr of judgeResults) {
  for (const s of jr.scores) {
    const t = totals.find(x => x.index === s.candidate)
    if (t) {
      t.sum += s.total
      t.count++
    }
  }
}
for (const t of totals) t.average = t.count ? Math.round((t.sum / t.count) * 10) / 10 : 0
totals.sort((x, y) => y.average - x.average)
const winner = candidates.find(c => c.index === totals[0].index)
const runnersUp = candidates.filter(c => c.index !== winner.index)
log(`勝者: 候補${winner.index}（${totals[0].average}点）`)

phase('統合')
const judgeComments = judgeResults
  .flatMap(jr => jr.scores)
  .map(s => `- 候補${s.candidate}（計${s.total}点）: ${s.rationale}`)
  .join('\n')

const finalDesign = await agent(
  `あなたは設計統合者です。審査で勝った設計をベースに、他候補の優れた部分を移植して最終設計書を作ってください。

設計課題: ${a.problem}${contextBrief}

勝者（候補${winner.index}、観点: ${winner.perspective}）:
${candidatesText}

審査員のコメント:
${judgeComments}

タスク: 勝者の設計をベースに、次点候補の明確に優れた要素（審査コメントで評価された点）だけを移植した最終設計書をMarkdownで書く。構成: ## 概要 / ## 構成要素と責務 / ## 重要な設計判断とその理由 / ## 採用しなかった代替案とその理由 / ## リスクと対策 / ## 実装順序の提案。移植した要素はどの候補由来か明記する。ファイルは変更せず、設計書全文をそのまま返答として返すこと。`,
  { label: 'synthesize', phase: '統合' }
)

return {
  status: '完了',
  winner: { candidate: winner.index, perspective: winner.perspective, average_score: totals[0].average },
  scores: totals,
  final_design_md: finalDesign || '統合エージェントが応答しませんでした。scores と候補情報から手動で判断してください',
}
