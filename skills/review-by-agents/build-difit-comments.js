#!/usr/bin/env node
'use strict'

/*
 * review-by-agents Step 6-A — 병합된 findings를 difit `--comment` 주입용 JSON으로 조립한다.
 *
 * 현행 SKILL.md 6-A가 하던 "finding마다 --comment '{...}' JSON을 손으로 조립(이스케이프·개행 포함)"을
 * 스크립트로 옮긴다. 메인 스레드는 병합된 findings를 파일로 넘기고, 스크립트가 뱉은 comments 파일을
 * `difit ... --comment "$(cat <commentsFile>)"`로 주입한다(배열 1개 = 여러 thread).
 *
 * 사용:
 *   node build-difit-comments.js --findings <findings.json> --out <디렉토리>
 *
 * 입력 findings.json: 병합·선별·정렬이 끝난 finding 배열. 각 항목:
 *   { severity, perspective, file, line, issue, suggestion?,
 *     suggestion_code?, language?, verifyNote?, side? }
 *
 * 출력:
 *   <out>/difit-comments.json  — difit `--comment` 주입용 thread 배열
 *   <out>/difit-baseline.json  — 6-D 대조용 [{file,line,body}] (프리로드 본문 baseline)
 *   stdout(JSON): { count, commentsFile, baselineFile }
 *
 * body 조립 규칙(6-A와 동일):
 *   1) [<심각도 이모지> <심각도> · <관점 이모지> <관점>] <issue>
 *   2) suggestion 있으면  빈 줄 + "제안: <suggestion>"
 *   3) suggestion_code 있으면  빈 줄 + ```<language> 코드펜스
 *   4) verifyNote 있으면  빈 줄 + "> <verifyNote>"
 * problem_code는 body에 넣지 않는다(코멘트가 해당 라인에 부착돼 diff에서 바로 보임 + 시크릿 유출 위험).
 */

const fs = require('node:fs')
const path = require('node:path')

const SEV_EMOJI = { critical: '🔴', warning: '🟡', info: '🔵' }
const SEV_LABEL = { critical: 'Critical', warning: 'Warning', info: 'Info' }
const PERSP_EMOJI = {
  Logic: '🧠',
  Convention: '📏',
  Security: '🛡️',
  Architecture: '🏛️',
  Design: '🎨',
}

function parseArgs(argv) {
  let findings = null
  let out = null
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--findings') findings = argv[++i]
    else if (argv[i] === '--out') out = argv[++i]
  }
  return { findings, out }
}

function buildBody(f) {
  const sevEmoji = SEV_EMOJI[f.severity] || '🔵'
  const sevLabel = SEV_LABEL[f.severity] || 'Info'
  const perspEmoji = PERSP_EMOJI[f.perspective] || ''
  const persp = f.perspective || ''
  const head = `[${sevEmoji} ${sevLabel} · ${perspEmoji} ${persp}] ${f.issue || ''}`.trim()

  const parts = [head]
  if (f.suggestion && String(f.suggestion).trim()) {
    parts.push(`제안: ${f.suggestion}`)
  }
  if (f.suggestion_code && String(f.suggestion_code).trim()) {
    const lang = f.language || ''
    parts.push('```' + lang + '\n' + f.suggestion_code + '\n```')
  }
  if (f.verifyNote && String(f.verifyNote).trim()) {
    parts.push(`> ${f.verifyNote}`)
  }
  return parts.join('\n\n')
}

function main() {
  const { findings, out } = parseArgs(process.argv.slice(2))
  if (!findings || !out) {
    process.stderr.write('사용법: build-difit-comments.js --findings <file> --out <dir>\n')
    process.exit(2)
  }

  let raw
  try {
    raw = JSON.parse(fs.readFileSync(findings, 'utf8'))
  } catch (e) {
    process.stderr.write(`findings 파일 파싱 실패: ${e.message}\n`)
    process.exit(2)
  }
  if (!Array.isArray(raw)) {
    process.stderr.write('findings는 배열이어야 함\n')
    process.exit(2)
  }

  const comments = []
  const baseline = []
  for (const f of raw) {
    if (!f || !f.file || f.line == null) {
      process.stderr.write(`skip: file·line 없는 finding — ${JSON.stringify(f)}\n`)
      continue
    }
    const body = buildBody(f)
    const side = f.side === 'old' ? 'old' : 'new'
    comments.push({
      type: 'thread',
      filePath: f.file,
      position: { side, line: f.line },
      body,
    })
    baseline.push({ file: f.file, line: f.line, body })
  }

  const commentsFile = path.join(out, 'difit-comments.json')
  const baselineFile = path.join(out, 'difit-baseline.json')
  fs.writeFileSync(commentsFile, JSON.stringify(comments), 'utf8')
  fs.writeFileSync(baselineFile, JSON.stringify(baseline), 'utf8')

  process.stdout.write(JSON.stringify({ count: comments.length, commentsFile, baselineFile }))
}

main()
