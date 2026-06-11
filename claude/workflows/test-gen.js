export const meta = {
  name: 'test-gen',
  description: 'テスト生成+mutation check。振る舞いを列挙してテストを書き、コードを意図的に壊してテストが検出することを確認する',
  whenToUse: '対象モジュールのテストを「本当にバグを検出できる」品質で整備したいとき。args.target に対象（ファイル/モジュール）が必須',
  phases: [
    { title: '分析', detail: '対象の振る舞いを列挙（happy/edge/error）' },
    { title: 'テスト作成', detail: 'テストを記述し全パスを確認' },
    { title: 'mutation check', detail: 'worktreeでコードを壊しテストが落ちることを確認' },
    { title: '強化', detail: 'mutationを検出できなかったテストを強化' },
  ],
}

const BEHAVIORS_SCHEMA = {
  type: 'object',
  properties: {
    behaviors: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          name: { type: 'string' },
          kind: { type: 'string', enum: ['happy', 'edge', 'error'] },
          description: { type: 'string' },
          importance: { type: 'number', description: '重要度 1-10' },
        },
        required: ['name', 'kind', 'description', 'importance'],
      },
    },
    existing_coverage: { type: 'string', description: '既存テストが既にカバーしている範囲の要約' },
  },
  required: ['behaviors', 'existing_coverage'],
}

const WRITE_SCHEMA = {
  type: 'object',
  properties: {
    all_passing: { type: 'boolean', description: '新規テスト含む全テストが通過したらtrue' },
    repo_root: { type: 'string', description: 'git rev-parse --show-toplevel の結果（絶対パス）' },
    test_files: { type: 'array', items: { type: 'string' }, description: 'リポジトリルートからの相対パス' },
    test_command: { type: 'string', description: '新規テストを実行するコマンド' },
    cases_written: { type: 'number' },
    failure_reason: { type: 'string', description: '失敗時の原因（実装のバグを発見した場合もここに書く）。成功時は空文字' },
  },
  required: ['all_passing', 'repo_root', 'test_files', 'test_command', 'cases_written', 'failure_reason'],
}

const MUTATION_SCHEMA = {
  type: 'object',
  properties: {
    killed: { type: 'boolean', description: '注入したバグをテストが検出（失敗）したらtrue' },
    mutant_description: { type: 'string', description: 'どのファイルにどんなバグを注入したか' },
    test_that_failed: { type: 'string', description: '検出したテスト名。検出されなかった場合は空文字' },
  },
  required: ['killed', 'mutant_description', 'test_that_failed'],
}

const STRENGTHEN_SCHEMA = {
  type: 'object',
  properties: {
    strengthened: { type: 'boolean' },
    summary: { type: 'string' },
  },
  required: ['strengthened', 'summary'],
}

const a = args || {}
if (!a.target) {
  return { status: '引数エラー', message: 'args.target に対象を渡してください。例: Workflow({name:"test-gen"}, {target:"src/payment/calculator.py"})' }
}
const maxMutants = a.max_mutants || 6

phase('分析')
const analysis = await agent(
  `あなたはテスト設計の専門家です。カレントディレクトリのリポジトリを読んで分析します（ファイル変更禁止）。

テスト対象: ${a.target}
${a.framework ? `テストフレームワーク: ${a.framework}` : ''}

タスク:
1. 対象コードを精読し、テストすべき振る舞いを列挙する（正常系 happy / 境界 edge / 異常系 error）
2. 既存テストを確認し、既にカバーされている振る舞いは含めない（existing_coverage に要約）
3. 各振る舞いに重要度1-10を付ける（壊れたときの実害の大きさで判断）

外部依存（DB・API・時刻）に触れる振る舞いは、モック可能な単位で切り出して列挙すること。`,
  { label: 'analyze', agentType: 'Explore', schema: BEHAVIORS_SCHEMA }
)

if (!analysis || !analysis.behaviors.length) {
  return { status: '分析失敗', message: '対象の振る舞いを抽出できませんでした。既存テストで十分カバーされているか、対象の指定を確認してください', existing_coverage: analysis ? analysis.existing_coverage : '' }
}
log(`テスト対象の振る舞い: ${analysis.behaviors.length}件`)

phase('テスト作成')
const behaviorList = analysis.behaviors
  .map(b => `- [${b.kind}] ${b.name}（重要度${b.importance}）: ${b.description}`)
  .join('\n')

let writeResult = null
const writeFailures = []
for (let attempt = 1; attempt <= 3; attempt++) {
  const history = writeFailures.length
    ? `\n\n過去の失敗:\n${writeFailures.map((f, i) => `試行${i + 1}: ${f}`).join('\n')}`
    : ''
  writeResult = await agent(
    `あなたはテスト実装者です。カレントディレクトリのリポジトリで作業します。

テスト対象: ${a.target}
${a.framework ? `テストフレームワーク: ${a.framework}` : 'フレームワークはプロジェクト構成から判定する'}

テストすべき振る舞い:
${behaviorList}

既存カバレッジ（重複させない）: ${analysis.existing_coverage}

タスク:
1. プロジェクトのテスト規約（配置・命名・スタイル）に従ってテストを書く
2. テストを実行し、新規テスト含む全テストが通過することを確認する
3. repo_root に git rev-parse --show-toplevel の結果、test_files にルートからの相対パスを入れる

厳守事項:
- 実装コードを変更しないこと。テストが実装のバグを発見した場合は、そのテストを削除・skip せず all_passing=false とし failure_reason にバグ内容を書く
- 既存テストを変更しないこと
- アサーションのない形だけのテストを書かないこと。各テストは振る舞いの具体的な期待値を検証する${history}`,
    { label: `write:attempt${attempt}`, phase: 'テスト作成', schema: WRITE_SCHEMA }
  )
  if (writeResult && writeResult.all_passing) break
  writeFailures.push(writeResult ? writeResult.failure_reason : 'エージェントが応答しませんでした')
  log(`テスト作成試行${attempt}が失敗`)
}

if (!writeResult || !writeResult.all_passing) {
  return {
    status: 'テスト作成失敗',
    note: '実装のバグを発見した可能性があります。failure内容を確認し、必要なら bug-fix ワークフローに引き継いでください',
    failures: writeFailures,
    behaviors: analysis.behaviors,
  }
}
log(`テスト${writeResult.cases_written}ケース作成完了（${writeResult.test_files.join(', ')}）`)

const mutationPrompt = (behavior) =>
  `あなたはmutation testingの実行者です。隔離されたgit worktree内で作業しています（メインのリポジトリとは別のコピーです）。

メインリポジトリ: ${writeResult.repo_root}
新規テスト（メインリポジトリ側にのみ存在）: ${writeResult.test_files.join(', ')}
テスト実行コマンド: ${writeResult.test_command}
テスト対象: ${a.target}

検証する振る舞い: ${behavior.name} — ${behavior.description}

手順:
1. 自分のworktreeルートを確認する（git rev-parse --show-toplevel）
2. メインリポジトリから新規テストファイルを自分のworktree内の同じ相対パスへコピーする（例: cp ${writeResult.repo_root}/<相対パス> <worktreeルート>/<相対パス>）
3. worktree内の実装コードに「${behavior.name}」を壊す現実的なバグを1つ注入する（テストファイルは変更しない）
4. テストを実行し、新規テストの少なくとも1つが失敗することを確認する → killed=true
5. どう壊してもテストが通ってしまう場合は killed=false（テストが弱い証拠）
6. 検証後は git checkout -- . で実装の変更を戻し、コピーしたテストファイルを削除して worktree をクリーンに戻す

コミットは禁止。メインリポジトリのファイルは一切変更しないこと。`

phase('mutation check')
const keyBehaviors = analysis.behaviors
  .slice()
  .sort((x, y) => y.importance - x.importance)
  .slice(0, maxMutants)
if (analysis.behaviors.length > maxMutants) {
  log(`mutation checkは重要度上位${maxMutants}件のみ実施（全${analysis.behaviors.length}件中。max_mutants引数で拡大可）`)
}

let mutationResults = (await parallel(keyBehaviors.map(b => () =>
  agent(mutationPrompt(b), {
    label: `mutate:${b.name.slice(0, 24)}`,
    phase: 'mutation check',
    isolation: 'worktree',
    schema: MUTATION_SCHEMA,
  }).then(m => m && ({ behavior: b, ...m }))
))).filter(Boolean)

phase('強化')
const weak = mutationResults.filter(m => !m.killed)
if (weak.length) {
  log(`${weak.length}件の振る舞いでmutationを検出できず。テストを強化します`)
  const strengthen = await agent(
    `あなたはテスト強化の実装者です。カレントディレクトリのリポジトリで作業します。

以下の振る舞いについて、mutation testing（コードを意図的に壊す検査）でテストがバグを検出できませんでした:
${weak.map(w => `- ${w.behavior.name}: 注入したバグ「${w.mutant_description}」が検出されなかった`).join('\n')}

対象テストファイル: ${writeResult.test_files.join(', ')}
テスト実行コマンド: ${writeResult.test_command}

タスク: 上記のバグを検出できるようにテストのアサーションを強化・追加し、（壊していない）現在のコードで全テストが通過することを確認する。実装コードは変更しないこと。`,
    { label: 'strengthen', phase: '強化', schema: STRENGTHEN_SCHEMA }
  )

  if (strengthen && strengthen.strengthened) {
    const rechecked = (await parallel(weak.map(w => () =>
      agent(mutationPrompt(w.behavior), {
        label: `re-mutate:${w.behavior.name.slice(0, 20)}`,
        phase: '強化',
        isolation: 'worktree',
        schema: MUTATION_SCHEMA,
      }).then(m => m && ({ behavior: w.behavior, ...m }))
    ))).filter(Boolean)
    const recheckedNames = new Set(rechecked.map(r => r.behavior.name))
    mutationResults = mutationResults
      .filter(m => !recheckedNames.has(m.behavior.name))
      .concat(rechecked)
  }
}

const killedCount = mutationResults.filter(m => m.killed).length
return {
  status: '完了',
  tests_added: writeResult.test_files,
  cases_written: writeResult.cases_written,
  mutation_score: `${killedCount}/${mutationResults.length}`,
  weak_behaviors: mutationResults
    .filter(m => !m.killed)
    .map(m => ({ behavior: m.behavior.name, undetected_mutant: m.mutant_description })),
  behaviors_total: analysis.behaviors.length,
  behaviors_mutation_checked: mutationResults.length,
}
