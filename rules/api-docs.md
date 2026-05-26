# API 문서 조회

내부 문서 중 일부는 SPA라 view URL을 그대로 WebFetch하면 빈 응답이 온다. 아래 도메인의 view URL을 보면 — 사용자 메시지든 Jira·Slack 본문에 섞여 있든 — 자동으로 API URL로 바꿔서 가져온다.

## docs.prnd.co.kr

```
View:  https://docs.prnd.co.kr/view/{PATH}?branch={BRANCH}
API:   https://docs.prnd.co.kr/api/files/content?branch={BRANCH}&path={urlencode(PATH)}
```

- `{PATH}`는 `path=` 쿼리로 옮기고 `/`를 `%2F`로 인코딩
- `{BRANCH}`는 양쪽 동일

예시:
- View: `https://docs.prnd.co.kr/view/docs/feature/HDS-18029/market_api.md?branch=feature%2FHDS-18029`
- API:  `https://docs.prnd.co.kr/api/files/content?branch=feature%2FHDS-18029&path=docs%2Ffeature%2FHDS-18029%2Fmarket_api.md`
