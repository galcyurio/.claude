// start-feature가 HDA 에픽을 만들 때 쓰는 순수 함수 모음. HTTP·CLI는 create-epic.mjs가 맡는다.

export const CUSTOM_FIELDS = {
  APP: 'customfield_10302',
  SPEC_DOC: 'customfield_10324', // 기획서
  DESIGN: 'customfield_10325', // 디자인
  SLACK_CHANNEL: 'customfield_10326', // 슬랙 채널
}

// 기획 Jira 제목에서 앞뒤 공백과 맨 앞 `ftr-` 하나를 걷어 낸다. 나머지는 원문 그대로 둔다.
export function cleanSummary(raw) {
  return raw.trim().replace(/^ftr-/, '').trim()
}

// 미배포·미보관 버전을 앱 이름("고객 7.94.0" -> "고객")별로 묶는다.
// 앱 접두어가 없는 버전(예: "미정")은 어느 앱에서나 고를 수 있게 common에 둔다.
export function groupVersionsByApp(versions) {
  const apps = {}
  const common = []
  for (const v of versions) {
    if (v.released || v.archived) continue
    const item = { id: v.id, name: v.name }
    const match = v.name.match(/^(.+?)\s+\d/)
    if (match) (apps[match[1]] ??= []).push(item)
    else common.push(item)
  }
  const sorted = {}
  for (const key of Object.keys(apps).sort()) sorted[key] = apps[key]
  return { apps: sorted, common }
}

function linkSection(title, url) {
  const body = url
    ? { type: 'paragraph', content: [{ type: 'text', text: url, marks: [{ type: 'link', attrs: { href: url } }] }] }
    : { type: 'paragraph', content: [{ type: 'text', text: '-' }] }
  return [{ type: 'heading', attrs: { level: 3 }, content: [{ type: 'text', text: title }] }, body]
}

// 팀 스크립트(create_jira_epic.mjs)와 같은 필드로 에픽 생성 요청을 만든다.
// summary에는 이름만 넣는다. Jira automation이 생성 뒤 [App][이름]으로 감싼다.
export function buildEpicFields({ parentKey, app, versionIds, name, links }) {
  return {
    project: { key: 'HDA' },
    issuetype: { id: '10000' },
    summary: name,
    parent: { key: parentKey },
    fixVersions: [...new Set(versionIds)].map((id) => ({ id })),
    [CUSTOM_FIELDS.APP]: { value: app },
    description: {
      type: 'doc',
      version: 1,
      content: [
        ...linkSection('기획서', links.spec),
        ...linkSection('디자인', links.design),
        ...linkSection('슬랙 채널', links.slack),
      ],
    },
  }
}

// automation 반영을 기다리는 동안 다음 동작을 정한다.
// 최종형이면 끝, 아직 입력값 그대로면 기다리고, 그 밖(감싼 형태가 다르거나 시간 초과)은 직접 설정한다.
export function decideSummaryAction({ current, input, final, timedOut }) {
  if (current === final) return 'done'
  if (current === input && !timedOut) return 'wait'
  return 'set'
}
