#!/usr/bin/env node
// start-feature가 HDA 에픽을 만들 때 부르는 비대화형 CLI. stdout에는 JSON 한 줄, 진행 메시지는 stderr.
//
//   create-epic.mjs info <HD-키>
//   create-epic.mjs create --parent <HD-키> --app <App> --version-id <id> [--version-id <id>...]
//                          --name <이름> [--spec <url>] [--design <url>] [--slack <url>] [--assign-me] [--dry-run]
//   create-epic.mjs wait-summary <에픽키> --input <이름> --final <최종 제목> [--timeout 180] [--dry-run]
//
// --dry-run에서는 Jira에 쓰는 요청(POST/PUT)을 보내지 않고 보낼 내용만 출력한다.
// 인증은 팀 스크립트와 같은 ~/.prnd/config.json(email)과 ~/.prnd/jira_token을 쓴다.
import fs from 'node:fs'
import path from 'node:path'
import { parseArgs } from 'node:util'
import { CUSTOM_FIELDS, cleanSummary, groupVersionsByApp, buildEpicFields, decideSummaryAction } from './epic-lib.mjs'

const JIRA_BASE_URL = 'https://prndcompany.atlassian.net'
const DRY_RUN_KEY = 'HDA-DRYRUN'
const POLL_INTERVAL_SEC = 10

const log = (msg) => process.stderr.write(`${msg}\n`)

function jiraRequest() {
  const home = process.env.HOME
  const { email } = JSON.parse(fs.readFileSync(path.join(home, '.prnd/config.json'), 'utf8'))
  const token = fs.readFileSync(path.join(home, '.prnd/jira_token'), 'utf8').trim()
  const auth = Buffer.from(`${email}:${token}`).toString('base64')
  return async (method, apiPath, body) => {
    const res = await fetch(`${JIRA_BASE_URL}${apiPath}`, {
      method,
      headers: { Authorization: `Basic ${auth}`, Accept: 'application/json', 'Content-Type': 'application/json' },
      body: body === undefined ? undefined : JSON.stringify(body),
    })
    const text = await res.text()
    if (!res.ok) throw new Error(`Jira ${method} ${apiPath} 실패 (${res.status}): ${text}`)
    return text ? JSON.parse(text) : {}
  }
}

export async function info(parentKey, request) {
  const fields = ['summary', CUSTOM_FIELDS.SPEC_DOC, CUSTOM_FIELDS.DESIGN, CUSTOM_FIELDS.SLACK_CHANNEL].join(',')
  const issue = await request('GET', `/rest/api/3/issue/${parentKey}?fields=${fields}`)
  const versions = await request('GET', '/rest/api/3/project/HDA/versions')
  const rawSummary = issue.fields.summary
  return {
    parentKey,
    rawSummary,
    name: cleanSummary(rawSummary),
    links: {
      spec: issue.fields[CUSTOM_FIELDS.SPEC_DOC] ?? null,
      design: issue.fields[CUSTOM_FIELDS.DESIGN] ?? null,
      slack: issue.fields[CUSTOM_FIELDS.SLACK_CHANNEL] ?? null,
    },
    ...groupVersionsByApp(versions),
  }
}

export async function createEpic(opts, request) {
  const fields = buildEpicFields(opts)
  const body = { fields }
  if (opts.dryRun) {
    log(`(dry-run) 에픽 생성 요청${opts.assignMe ? ' + 담당자 본인 지정' : ''}을 보내지 않습니다`)
    return { key: DRY_RUN_KEY, url: null, dryRun: true, request: body }
  }
  const created = await request('POST', '/rest/api/3/issue', body)
  log(`에픽 생성: ${created.key}`)
  if (opts.assignMe) {
    const me = await request('GET', '/rest/api/3/myself')
    await request('PUT', `/rest/api/3/issue/${created.key}/assignee`, { accountId: me.accountId })
    log('담당자를 본인으로 지정했습니다')
  }
  return { key: created.key, url: `${JIRA_BASE_URL}/browse/${created.key}`, dryRun: false, request: body }
}

// automation이 summary를 [App][이름]으로 감쌀 때까지 기다린 뒤, 최종형이 아니면 직접 설정한다.
export async function waitSummary({ key, input, final, timeoutSec, dryRun }, request, sleep) {
  if (dryRun) {
    log(`(dry-run) ${key} 제목을 "${final}"(으)로 맞춥니다`)
    return { key, summary: final, action: 'set' }
  }
  let elapsed = 0
  for (;;) {
    const issue = await request('GET', `/rest/api/3/issue/${key}?fields=summary`)
    const current = issue.fields.summary
    const action = decideSummaryAction({ current, input, final, timedOut: elapsed >= timeoutSec })
    if (action === 'done') return { key, summary: current, action }
    if (action === 'set') {
      await request('PUT', `/rest/api/3/issue/${key}`, { fields: { summary: final } })
      log(`제목을 "${final}"(으)로 설정했습니다 (이전: "${current}")`)
      return { key, summary: final, action }
    }
    await sleep(POLL_INTERVAL_SEC)
    elapsed += POLL_INTERVAL_SEC
  }
}

async function main() {
  const { values, positionals } = parseArgs({
    allowPositionals: true,
    options: {
      parent: { type: 'string' },
      app: { type: 'string' },
      'version-id': { type: 'string', multiple: true },
      name: { type: 'string' },
      spec: { type: 'string' },
      design: { type: 'string' },
      slack: { type: 'string' },
      'assign-me': { type: 'boolean', default: false },
      input: { type: 'string' },
      final: { type: 'string' },
      timeout: { type: 'string', default: '180' },
      'dry-run': { type: 'boolean', default: false },
    },
  })
  const [command, target] = positionals
  const need = (v, flag) => {
    if (!v) throw new Error(`${flag} 값이 필요합니다`)
    return v
  }
  const dryRun = values['dry-run']
  // dry-run의 wait-summary는 요청을 보내지 않으므로 인증 파일 없이도 돌게 한다.
  const request = command === 'wait-summary' && dryRun ? async () => { throw new Error('dry-run 중 요청') } : jiraRequest()
  let result
  if (command === 'info') {
    result = await info(need(target, '<HD-키>'), request)
  } else if (command === 'create') {
    result = await createEpic({
      parentKey: need(values.parent, '--parent'),
      app: need(values.app, '--app'),
      versionIds: need(values['version-id'], '--version-id'),
      name: need(values.name, '--name'),
      links: { spec: values.spec ?? null, design: values.design ?? null, slack: values.slack ?? null },
      assignMe: values['assign-me'],
      dryRun,
    }, request)
  } else if (command === 'wait-summary') {
    result = await waitSummary({
      key: need(target, '<에픽키>'),
      input: need(values.input, '--input'),
      final: need(values.final, '--final'),
      timeoutSec: Number(values.timeout),
      dryRun,
    }, request, (sec) => new Promise((r) => setTimeout(r, sec * 1000)))
  } else {
    throw new Error(`알 수 없는 명령: ${command ?? '(없음)'} (info | create | wait-summary)`)
  }
  process.stdout.write(`${JSON.stringify(result)}\n`)
}

if (import.meta.main) {
  main().catch((e) => {
    log(`[오류] ${e.message}`)
    process.exit(1)
  })
}
