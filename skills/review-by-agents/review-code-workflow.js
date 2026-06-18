export const meta = {
  name: 'review-by-agents-code',
  description: '코드 변경을 다관점 병렬 리뷰하고 Critical·머지차단 finding을 교차검증한다',
  phases: [
    { title: 'Find', detail: 'Logic+Convention / Security / Architecture 관점 병렬 리뷰' },
    { title: 'Verify', detail: 'Critical·머지차단 finding을 refute 검증자 2명으로 교차검증' },
  ],
}

// args: { diff, changedFiles, contextSummary, followupContext, targetDesc }
// 런타임이 args를 JSON 문자열로 넘기는 경우가 있어 파싱 후 사용한다(객체로 오면 그대로).
const _args = typeof args === 'string' ? JSON.parse(args) : (args || {})
const { diff = '', changedFiles = [], contextSummary = '', followupContext = '', targetDesc = '' } = _args

// fail-fast: args 미전달/파싱 후에도 빈 diff면 finder가 엉뚱한 결과를 내는 silent failure 방지
if (!String(diff).trim()) {
  throw new Error('review-by-agents: args.diff가 비어 있음 — Workflow args 미전달 의심. 메인 스레드는 수동 Agent 병렬 스폰 폴백으로 전환할 것.')
}

const FINDINGS_SCHEMA = {
  type: 'object',
  required: ['findings'],
  additionalProperties: false,
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['severity', 'perspective', 'file', 'line', 'issue', 'mergeBlocking', 'problem_code', 'language', 'suggestion'],
        properties: {
          severity: { type: 'string', enum: ['critical', 'warning', 'info'] },
          perspective: { type: 'string', enum: ['Logic', 'Convention', 'Security', 'Architecture'] },
          file: { type: 'string' },
          line: { type: 'integer' },
          issue: { type: 'string' },
          mergeBlocking: { type: 'boolean' },
          problem_code: { type: 'string' },
          language: { type: 'string' },
          suggestion: { type: 'string' },
          suggestion_code: { type: 'string' },
        },
      },
    },
  },
}

const VERDICT_SCHEMA = {
  type: 'object',
  required: ['refuted', 'confidence', 'reason'],
  additionalProperties: false,
  properties: {
    refuted: { type: 'boolean' },
    confidence: { type: 'string', enum: ['high', 'med', 'low'] },
    reason: { type: 'string' },
  },
}

const EXCLUSION_RULES = `다음에 해당하면 명백한 문제처럼 보여도 issue로 보고하지 않는다(의도된 임시 상태 + 후속 작업 보장):
- TODO/FIXME 주석 + 후속 작업(이슈/PR 번호) 명시
- 명시적 placeholder/stub + "추후 구현" 의도 표시
- 시리즈 PR의 중간 단계임이 본문에 명시
- production 경로 mock/sample 데이터 + 후속 데이터 연결 작업 명시
단, 다음은 면제에서 제외하고 정상 보고한다:
- 주석이 모호하거나 후속 위치가 명시되지 않은 경우
- 머지 순간 빌드/테스트가 깨지거나, 시크릿/PII/공격표면이 외부 노출되거나, DB/사용자 자산 데이터 유실·손상이 발생하는 경우(이때 mergeBlocking=true)`

const PERSPECTIVES = [
  {
    label: 'logic-convention',
    checklist: `- Logic: 버그, null safety, 경계 조건, 에러 핸들링 누락, 레이스 컨디션
- Convention: 네이밍 일관성, 프로젝트 패턴, 코드 중복, 매직 넘버
(perspective 필드는 Logic 또는 Convention 중 해당하는 값으로 태깅)`,
    opts: {},
  },
  {
    label: 'security',
    checklist: `- Security: 인젝션(SQL/XSS/SSRF), 인증/인가 우회, 민감정보 노출, 안전하지 않은 API 사용
(perspective 필드는 항상 Security)`,
    opts: {},
  },
  {
    label: 'architecture',
    checklist: `- Architecture: 의존성 방향 위반, 레이어 위반, 단일 책임 위반, 불필요한 결합 도입
(perspective 필드는 항상 Architecture)`,
    opts: { agentType: 'Oracle' },
  },
]

function finderPrompt(checklist) {
  return `## REVIEW SCOPE
${diff}

## PERSPECTIVE
${checklist}

## CONTEXT
변경 파일: ${changedFiles.join(', ')}
${contextSummary}

## CONTEXT — TODO / 후속 작업 / 시리즈 정보
${followupContext}

## 보고 제외 기준
${EXCLUSION_RULES}

## OUTPUT
정말 중요한 이슈만 보고하라. 사소한 스타일·네이밍 지적은 제외하고 실제 버그·취약점·구조 결함·사용자 영향 위주로 선별하라. 개수 하드캡은 없다. severity를 정확히 태깅하고, mergeBlocking은 "머지 순간 빌드/보안/데이터에 실제 영향"일 때만 true로 둔다. 이슈가 없으면 빈 배열을 반환하라.`
}

const SEV_RANK = { critical: 3, warning: 2, info: 1 }

function downgrade(sev) {
  if (sev === 'critical') return 'warning'
  return 'info'
}

function needsVerify(f) {
  return f.severity === 'critical' || (f.severity === 'warning' && f.mergeBlocking === true)
}

async function verifyFinding(f) {
  const lenses = [
    {
      name: '정확성',
      q: `다음 리뷰 finding이 실제 코드에서 참인지 검증하라. diff와 해당 파일(${f.file})을 Read해 직접 확인하라. 참임을 확신할 수 없으면 refuted=true로 답하라.`,
    },
    {
      name: '머지영향',
      q: `다음 리뷰 finding이 머지되는 순간 실제로 빌드/보안/데이터에 영향을 주는지 검증하라. 영향을 확신할 수 없으면 refuted=true로 답하라.`,
    },
  ]
  const findingText = JSON.stringify({
    severity: f.severity,
    perspective: f.perspective,
    file: f.file,
    line: f.line,
    issue: f.issue,
    problem_code: f.problem_code,
  })
  const verdicts = (await parallel(lenses.map((l) => () =>
    agent(`${l.q}\n\nFINDING:\n${findingText}\n\nDIFF:\n${diff}`, {
      label: `verify:${l.name}:${f.file}`,
      phase: 'Verify',
      schema: VERDICT_SCHEMA,
    })
  ))).filter(Boolean)

  const refutes = verdicts.filter((v) => v.refuted).length
  if (refutes === 0) {
    return { ...f, verifyNote: '검증: 정확성·머지영향 2/2 확인' }
  }
  if (refutes === 1) {
    const next = downgrade(f.severity)
    return { ...f, severity: next, verifyNote: `검증: 1/2 refute → ${next} 강등` }
  }
  return { ...f, severity: 'info', mergeBlocking: false, verifyNote: '검증: 2/2 refute → 낮은 신뢰도(info 강등)' }
}

phase('Find')
const reviewed = await pipeline(
  PERSPECTIVES,
  (p) => agent(finderPrompt(p.checklist), {
    label: `find:${p.label}`,
    phase: 'Find',
    schema: FINDINGS_SCHEMA,
    ...p.opts,
  }),
  (result) => {
    const findings = (result && result.findings) || []
    return parallel(findings.map((fd) => () =>
      needsVerify(fd) ? verifyFinding(fd) : Promise.resolve(fd)
    ))
  }
)

const all = reviewed.flat().filter(Boolean)

// dedup by file:line — keep higher severity
const byKey = new Map()
for (const f of all) {
  const k = `${f.file}:${f.line}`
  const ex = byKey.get(k)
  if (!ex || SEV_RANK[f.severity] > SEV_RANK[ex.severity]) byKey.set(k, f)
}
const deduped = [...byKey.values()]

function sortFindings(arr) {
  return arr.slice().sort((a, b) =>
    SEV_RANK[b.severity] - SEV_RANK[a.severity] ||
    (a.file < b.file ? -1 : a.file > b.file ? 1 : 0) ||
    a.line - b.line
  )
}

// select: critical 전량 보존 + non-critical 최대 5
const criticals = deduped.filter((f) => f.severity === 'critical')
const nonCriticals = sortFindings(deduped.filter((f) => f.severity !== 'critical')).slice(0, 5)
const codeIssues = sortFindings([...criticals, ...nonCriticals])

const verifyStats = {
  criticalConfirmed: codeIssues.filter((f) => f.severity === 'critical').length,
  verified: all.filter((f) => f.verifyNote).length,
  downgraded: all.filter((f) => f.verifyNote && f.verifyNote.includes('강등')).length,
}

log(`코드 리뷰 완료 — 이슈 ${codeIssues.length}건(Critical ${verifyStats.criticalConfirmed}), 검증 ${verifyStats.verified}건 중 강등 ${verifyStats.downgraded}건`)

return { targetDesc, codeIssues, verifyStats }
