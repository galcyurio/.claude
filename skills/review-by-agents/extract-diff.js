#!/usr/bin/env node
'use strict'

/*
 * review-by-agents Step 1 — 입력 파싱 + diff 추출.
 *
 * 현행 SKILL.md 1단계가 하던 순차 shell 왕복(인자 판별 → base 감지 → diff → 빈/3000행 가드)을
 * 한 번의 호출로 접는다. 메인 스레드는 이 스크립트를 1회 실행하고 stdout JSON만 파싱하면 된다.
 *
 * 사용:
 *   node extract-diff.js [<PR URL | 파일경로 | 없음>] [--out <diff 저장 경로>] [--max-lines <N>]
 *
 * stdout(항상 단일 JSON 객체):
 *   {
 *     mode: 'pr' | 'file' | 'diff',
 *     targetDesc: string,          // "PR #12" | "<path>" | "<base>...HEAD"
 *     base: string|null,           // diff 모드만
 *     prNumber: number|null,       // pr 모드만
 *     changedFiles: string[],
 *     diffLines: number,
 *     empty: boolean,              // true → 메인은 "리뷰할 변경사항이 없습니다" 출력 후 종료
 *     oversized: boolean,          // diffLines > maxLines → 메인은 분할 리뷰를 AskUserQuestion
 *     diffFile: string|null,       // 전체 diff/파일내용을 담은 파일 경로 (메인이 Read해 workflow diff arg로 전달)
 *     error: string|null           // 실패 시 사유 (메인은 수동 폴백 판단)
 *   }
 *
 * diff 본문은 stdout에 싣지 않고 diffFile에 쓴다(거대 diff로 stdout이 오염되는 것을 방지).
 */

const { execFileSync } = require('node:child_process')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')

const DEFAULT_MAX_LINES = 3000

function parseArgs(argv) {
  const rest = []
  let out = null
  let maxLines = DEFAULT_MAX_LINES
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]
    if (a === '--out') {
      out = argv[++i]
    } else if (a === '--max-lines') {
      maxLines = parseInt(argv[++i], 10) || DEFAULT_MAX_LINES
    } else {
      rest.push(a)
    }
  }
  return { target: rest[0], out, maxLines }
}

/** shell 명령 실행. 성공 시 stdout(trim 안 함), 실패 시 null. */
function run(cmd, args, opts = {}) {
  try {
    return execFileSync(cmd, args, {
      encoding: 'utf8',
      maxBuffer: 64 * 1024 * 1024,
      stdio: ['ignore', 'pipe', 'ignore'],
      ...opts,
    })
  } catch {
    return null
  }
}

function countLines(text) {
  if (!text) return 0
  const n = text.split('\n').length
  // 파일이 개행으로 끝나면 마지막 빈 조각을 빼서 실제 라인 수를 센다.
  return text.endsWith('\n') ? n - 1 : n
}

function classify(target) {
  if (!target) return { mode: 'diff' }
  if (/github\.com/.test(target)) {
    const m = target.match(/\/pull\/(\d+)/)
    return { mode: 'pr', prNumber: m ? parseInt(m[1], 10) : null }
  }
  if (/^\d+$/.test(target)) return { mode: 'pr', prNumber: parseInt(target, 10) }
  if (fs.existsSync(target) && fs.statSync(target).isFile()) {
    return { mode: 'file' }
  }
  return { mode: 'unknown' }
}

/** 현재 브랜치의 base 브랜치를 감지한다(네트워크 최소화). */
function detectBase() {
  // 1) 현재 브랜치에 연결된 PR의 base
  const pr = run('gh', ['pr', 'view', '--json', 'baseRefName', '-q', '.baseRefName'])
  if (pr && pr.trim()) return pr.trim()
  // 2) origin/HEAD 심볼릭 참조 (오프라인·즉시)
  const sym = run('git', ['symbolic-ref', '--short', 'refs/remotes/origin/HEAD'])
  if (sym && sym.trim()) return sym.trim().replace(/^origin\//, '')
  // 3) git remote show origin (네트워크)
  const show = run('git', ['remote', 'show', 'origin'])
  if (show) {
    const m = show.match(/HEAD branch:\s*(\S+)/)
    if (m) return m[1]
  }
  // 4) 관습적 기본 브랜치
  for (const b of ['main', 'master', 'develop']) {
    if (run('git', ['rev-parse', '--verify', '--quiet', b]) != null) return b
  }
  return null
}

function writeDiff(out, content) {
  const file = out || path.join(os.tmpdir(), `review-by-agents-diff-${process.pid}.patch`)
  fs.writeFileSync(file, content ?? '', 'utf8')
  return file
}

function emit(obj) {
  process.stdout.write(JSON.stringify(obj))
}

function main() {
  const { target, out, maxLines } = parseArgs(process.argv.slice(2))
  const cls = classify(target)

  const result = {
    mode: cls.mode,
    targetDesc: '',
    base: null,
    prNumber: cls.prNumber ?? null,
    changedFiles: [],
    diffLines: 0,
    empty: false,
    oversized: false,
    diffFile: null,
    error: null,
  }

  if (cls.mode === 'unknown') {
    result.error = `인자를 PR URL·PR 번호·기존 파일 경로 어느 것으로도 해석할 수 없음: ${target}`
    emit(result)
    return
  }

  if (cls.mode === 'file') {
    let content
    try {
      content = fs.readFileSync(target, 'utf8')
    } catch (e) {
      result.error = `파일을 읽을 수 없음: ${target} (${e.message})`
      emit(result)
      return
    }
    result.targetDesc = target
    result.changedFiles = [target]
    result.diffLines = countLines(content)
    result.empty = content.trim().length === 0
    result.oversized = result.diffLines > maxLines
    result.diffFile = writeDiff(out, content)
    emit(result)
    return
  }

  if (cls.mode === 'pr') {
    if (result.prNumber == null) {
      result.error = 'PR URL에서 번호를 추출하지 못함'
      emit(result)
      return
    }
    result.targetDesc = `PR #${result.prNumber}`
    const num = String(result.prNumber)
    const diff = run('gh', ['pr', 'diff', num])
    if (diff == null) {
      result.error = `gh pr diff ${num} 실패 (인증·네트워크·존재 여부 확인)`
      emit(result)
      return
    }
    const names = run('gh', ['pr', 'diff', num, '--name-only'])
    result.changedFiles = names ? names.split('\n').filter(Boolean) : []
    result.diffLines = countLines(diff)
    result.empty = diff.trim().length === 0
    result.oversized = result.diffLines > maxLines
    result.diffFile = writeDiff(out, diff)
    emit(result)
    return
  }

  // mode === 'diff' (현재 변경사항)
  const base = detectBase()
  if (!base) {
    result.error = 'base 브랜치를 감지하지 못함'
    emit(result)
    return
  }
  result.base = base
  result.targetDesc = `${base}...HEAD`
  const range = `${base}...HEAD`
  const diff = run('git', ['diff', range])
  if (diff == null) {
    result.error = `git diff ${range} 실패`
    emit(result)
    return
  }
  const names = run('git', ['diff', range, '--name-only'])
  result.changedFiles = names ? names.split('\n').filter(Boolean) : []
  result.diffLines = countLines(diff)
  result.empty = diff.trim().length === 0
  result.oversized = result.diffLines > maxLines
  result.diffFile = writeDiff(out, diff)
  emit(result)
}

main()
