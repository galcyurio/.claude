import test from 'node:test'
import assert from 'node:assert/strict'
import { createEpic, waitSummary } from './create-epic.mjs'

// 호출을 기록하고 정해 둔 응답을 돌려주는 가짜 Jira 요청 함수
function fakeRequest(responses = {}) {
  const calls = []
  const request = async (method, path, body) => {
    calls.push({ method, path, body })
    const r = responses[`${method} ${path}`]
    return typeof r === 'function' ? r() : (r ?? {})
  }
  return { calls, request }
}

const epicOpts = { parentKey: 'HD-720', app: '고객', versionIds: ['1'], name: '이름', links: { spec: null, design: null, slack: null } }

test('createEpic dry-run은 GET 외 요청을 하지 않는다', async () => {
  const { calls, request } = fakeRequest()
  const r = await createEpic({ ...epicOpts, assignMe: true, dryRun: true }, request)
  assert.ok(calls.every((c) => c.method === 'GET'))
  assert.equal(r.key, 'HDA-DRYRUN')
  assert.equal(r.request.fields.summary, '이름')
})

test('createEpic assign-me는 POST 뒤 myself의 accountId로 PUT assignee', async () => {
  const { calls, request } = fakeRequest({
    'POST /rest/api/3/issue': { key: 'HDA-1' },
    'GET /rest/api/3/myself': { accountId: 'A' },
  })
  const r = await createEpic({ ...epicOpts, assignMe: true, dryRun: false }, request)
  assert.equal(r.key, 'HDA-1')
  const put = calls.find((c) => c.method === 'PUT')
  assert.equal(put.path, '/rest/api/3/issue/HDA-1/assignee')
  assert.deepEqual(put.body, { accountId: 'A' })
})

test('waitSummary 타임아웃이면 final로 PUT', async () => {
  const { calls, request } = fakeRequest({
    'GET /rest/api/3/issue/HDA-1?fields=summary': { fields: { summary: '이름' } },
  })
  const r = await waitSummary({ key: 'HDA-1', input: '이름', final: '[고객][이름]', timeoutSec: 0 }, request, async () => {})
  const put = calls.find((c) => c.method === 'PUT')
  assert.equal(put.path, '/rest/api/3/issue/HDA-1')
  assert.deepEqual(put.body, { fields: { summary: '[고객][이름]' } })
  assert.equal(r.action, 'set')
})

test('waitSummary는 automation이 최종형으로 감싸면 PUT 없이 끝난다', async () => {
  let n = 0
  const { calls, request } = fakeRequest({
    'GET /rest/api/3/issue/HDA-1?fields=summary': () => ({ fields: { summary: n++ === 0 ? '이름' : '[고객][이름]' } }),
  })
  const r = await waitSummary({ key: 'HDA-1', input: '이름', final: '[고객][이름]', timeoutSec: 180 }, request, async () => {})
  assert.equal(r.action, 'done')
  assert.ok(calls.every((c) => c.method === 'GET'))
})

test('waitSummary dry-run은 요청 없이 action set을 출력만 한다', async () => {
  const { calls, request } = fakeRequest()
  const r = await waitSummary({ key: 'HDA-DRYRUN', input: '이름', final: '[고객][이름]', timeoutSec: 180, dryRun: true }, request, async () => {})
  assert.equal(calls.length, 0)
  assert.equal(r.action, 'set')
})
