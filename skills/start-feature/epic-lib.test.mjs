import test from 'node:test'
import assert from 'node:assert/strict'
import { cleanSummary, groupVersionsByApp, buildEpicFields, decideSummaryAction } from './epic-lib.mjs'

test('cleanSummary', () => {
  assert.equal(cleanSummary(' ftr-팔기-평가사-평가완료-백그라운드-전송'), '팔기-평가사-평가완료-백그라운드-전송')
  assert.equal(cleanSummary('ftr-사기 고객 슬라이더 직접입력'), '사기 고객 슬라이더 직접입력')
  assert.equal(cleanSummary('중숨이 리스트 뷰 추가'), '중숨이 리스트 뷰 추가')
  assert.equal(cleanSummary('ftr-ftr-x'), 'ftr-x')
})

test('groupVersionsByApp', () => {
  const r = groupVersionsByApp([
    { id: '1', name: '고객 7.144.0', released: false, archived: false },
    { id: '2', name: '테크베이-콜 1.2.0', released: false, archived: false },
    { id: '3', name: '미정', released: false, archived: false },
    { id: '4', name: '고객 7.143.0', released: true, archived: false },
  ])
  assert.deepEqual(Object.keys(r.apps), ['고객', '테크베이-콜'])
  assert.deepEqual(r.apps['고객'], [{ id: '1', name: '고객 7.144.0' }])
  assert.deepEqual(r.common, [{ id: '3', name: '미정' }])
})

test('buildEpicFields', () => {
  const f = buildEpicFields({ parentKey: 'HD-720', app: '고객', versionIds: ['1', '9'], name: '헤이딜러 로딩 심볼 변경', links: { spec: 'https://n', design: null, slack: 'https://s' } })
  assert.equal(f.project.key, 'HDA')
  assert.equal(f.issuetype.id, '10000')
  assert.equal(f.parent.key, 'HD-720')
  assert.deepEqual(f.fixVersions, [{ id: '1' }, { id: '9' }])
  assert.deepEqual(f.customfield_10302, { value: '고객' })
  assert.equal(f.summary, '헤이딜러 로딩 심볼 변경')
  assert.equal(f.description.content[3].content[0].text, '-') // 디자인 없음
  assert.equal(f.description.content[1].content[0].marks[0].attrs.href, 'https://n')
})

test('decideSummaryAction', () => {
  const base = { input: '이름', final: '[고객][이름]' }
  assert.equal(decideSummaryAction({ ...base, current: '이름', timedOut: false }), 'wait')
  assert.equal(decideSummaryAction({ ...base, current: '[고객][이름]', timedOut: false }), 'done')
  assert.equal(decideSummaryAction({ ...base, current: '이름', timedOut: true }), 'set')
  assert.equal(decideSummaryAction({ input: '이름', final: '[공통][이름]', current: '[고객][이름]', timedOut: false }), 'set')
})
