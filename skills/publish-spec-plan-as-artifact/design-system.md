# spec/plan 아티팩트 디자인 시스템

`publish-spec-plan-as-artifact` 스킬이 매 렌더에 쓰는 **고정 디자인 시스템**. CSS/JS는 그대로 인라인하고, 컴포넌트 HTML은 문서 내용으로 채운다. **룩은 고정, 콘텐츠 구조는 문서에 맞춰 적응**(하이브리드).

## 원칙

- **실용형 문서 트리트먼트** — 플래시 히어로 금지. 강한 타이포 위계 + 절제된 색 + 넉넉한 여백.
- **색**: 쿨 슬레이트 중립 + 시그널 인디고 액센트. 단계를 색으로 인코딩 — 정의=인디고(`--accent`), 배선=틸(`--wire`), 커밋 게이트/검증=그린(`--commit`), setup=그레이(`--setup`), 리스크=앰버(`--warn`).
- **타입**: 시스템 한글 산세(Apple SD Gothic Neo 스택) + 시스템 모노(SF Mono) 2역할. CJK webfont data URI는 비현실적(수 MB)이라 시스템 스택이 **의도적 선택**. 이벤트명·식별자·번호·키는 모노로.
- **다크/라이트 양쪽** 토큰. `@media prefers-color-scheme` + `[data-theme]` 오버라이드 둘 다.
- **문서별 적응**: 아래 "적응 규칙" 참조. 파이프라인·wave·매트릭스는 문서 구조가 요구할 때만 그린다.

## 1. Style — 그대로 인라인

```html
<style>
  :root {
    --font-sans: -apple-system, BlinkMacSystemFont, "Apple SD Gothic Neo", Pretendard, "Noto Sans KR", system-ui, "Segoe UI", Roboto, sans-serif;
    --font-mono: "SF Mono", ui-monospace, "JetBrains Mono", "Cascadia Code", Menlo, Consolas, monospace;
    --ground: #f4f6f8; --surface: #ffffff; --surface-2: #eceff4;
    --ink: #161b22; --ink-soft: #39424f; --muted: #656e7c;
    --line: #e0e5ec; --line-soft: #eceef3;
    --accent: #3a53c5; --wire: #0c8478; --commit: #2c8a4c; --warn: #a75c07; --setup: #6b7280;
    --shadow: 0 1px 2px rgba(20,25,35,.04), 0 8px 24px -12px rgba(20,25,35,.12);
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --ground: #0c0f14; --surface: #14181f; --surface-2: #1a212b;
      --ink: #e8ebf1; --ink-soft: #b9c1cd; --muted: #808a98;
      --line: #242c37; --line-soft: #1b222c;
      --accent: #8296ff; --wire: #34d3bf; --commit: #5bc880; --warn: #efb44d; --setup: #8b95a3;
      --shadow: 0 1px 2px rgba(0,0,0,.3), 0 12px 32px -14px rgba(0,0,0,.6);
    }
  }
  :root[data-theme="light"] {
    --ground: #f4f6f8; --surface: #ffffff; --surface-2: #eceff4;
    --ink: #161b22; --ink-soft: #39424f; --muted: #656e7c;
    --line: #e0e5ec; --line-soft: #eceef3;
    --accent: #3a53c5; --wire: #0c8478; --commit: #2c8a4c; --warn: #a75c07; --setup: #6b7280;
    --shadow: 0 1px 2px rgba(20,25,35,.04), 0 8px 24px -12px rgba(20,25,35,.12);
  }
  :root[data-theme="dark"] {
    --ground: #0c0f14; --surface: #14181f; --surface-2: #1a212b;
    --ink: #e8ebf1; --ink-soft: #b9c1cd; --muted: #808a98;
    --line: #242c37; --line-soft: #1b222c;
    --accent: #8296ff; --wire: #34d3bf; --commit: #5bc880; --warn: #efb44d; --setup: #8b95a3;
    --shadow: 0 1px 2px rgba(0,0,0,.3), 0 12px 32px -14px rgba(0,0,0,.6);
  }
  * { box-sizing: border-box; }
  body { margin: 0; background: var(--ground); color: var(--ink); font-family: var(--font-sans); font-size: 16px; line-height: 1.7; -webkit-font-smoothing: antialiased; text-rendering: optimizeLegibility; }
  @media (prefers-reduced-motion: no-preference) { html { scroll-behavior: smooth; } }
  .progress { position: fixed; top: 0; left: 0; height: 2px; width: 0; background: var(--accent); z-index: 50; transition: width .08s linear; }
  .wrap { max-width: 1220px; margin: 0 auto; padding: 0 clamp(18px, 4vw, 40px); }
  .doc { display: grid; grid-template-columns: minmax(0,1fr); gap: 0; padding: 40px 0 96px; }
  @media (min-width: 1060px) { .doc { grid-template-columns: 246px minmax(0,1fr); gap: 52px; } }
  .rail { display: none; }
  @media (min-width: 1060px) { .rail { display: block; position: sticky; top: 28px; align-self: start; max-height: calc(100vh - 56px); overflow: auto; font-size: .82rem; padding-right: 6px; } }
  .rail__title { font-family: var(--font-mono); font-size: .68rem; letter-spacing: .14em; text-transform: uppercase; color: var(--muted); margin: 0 0 14px; font-weight: 600; }
  .rail__wave { font-size: .68rem; letter-spacing: .1em; text-transform: uppercase; color: var(--muted); font-weight: 700; margin: 18px 0 7px; display: flex; align-items: center; gap: 7px; }
  .rail__wave::before { content: ""; width: 7px; height: 7px; border-radius: 2px; background: var(--dot, var(--muted)); }
  .rail a { display: flex; gap: 9px; align-items: baseline; color: var(--ink-soft); text-decoration: none; padding: 4px 8px; border-radius: 6px; margin: 1px 0; border-left: 2px solid transparent; }
  .rail a:hover { background: color-mix(in srgb, var(--accent) 8%, transparent); color: var(--ink); }
  .rail a.active { color: var(--ink); border-left-color: var(--accent); background: color-mix(in srgb, var(--accent) 10%, transparent); }
  .rail a .n { font-family: var(--font-mono); font-size: .72rem; color: var(--muted); font-variant-numeric: tabular-nums; }
  .rail a.active .n { color: var(--accent); }
  .eyebrow { font-family: var(--font-mono); font-size: .72rem; font-weight: 600; letter-spacing: .16em; text-transform: uppercase; color: var(--accent); }
  .masthead { padding-bottom: 34px; border-bottom: 1px solid var(--line); }
  .masthead h1 { font-size: clamp(1.9rem, 3.6vw, 2.7rem); line-height: 1.12; font-weight: 800; letter-spacing: -.022em; margin: 14px 0 0; text-wrap: balance; max-width: 20ch; }
  .masthead .lead { margin: 18px 0 0; font-size: 1.08rem; color: var(--ink-soft); max-width: 62ch; line-height: 1.62; }
  .masthead .lead strong { color: var(--ink); font-weight: 650; }
  .chips { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 24px; }
  .chip { display: inline-flex; align-items: center; gap: 7px; font-size: .8rem; padding: 5px 11px; border-radius: 999px; border: 1px solid var(--line); background: var(--surface); color: var(--ink-soft); }
  .chip b { color: var(--muted); font-weight: 600; font-family: var(--font-mono); font-size: .72rem; letter-spacing: .04em; text-transform: uppercase; }
  .chip code { font-family: var(--font-mono); font-size: .82em; color: var(--ink); }
  section { padding-top: 52px; }
  .sec-head { display: flex; align-items: baseline; gap: 14px; margin-bottom: 22px; }
  .sec-head h2 { font-size: 1.34rem; font-weight: 750; letter-spacing: -.01em; margin: 0; }
  .sec-head .kick { font-family: var(--font-mono); font-size: .72rem; letter-spacing: .12em; text-transform: uppercase; color: var(--muted); font-weight: 600; }
  .tldr { background: var(--surface); border: 1px solid var(--line); border-radius: 14px; padding: 26px 28px; box-shadow: var(--shadow); border-left: 3px solid var(--accent); }
  .tldr .headline { font-size: 1.12rem; font-weight: 700; line-height: 1.45; margin: 0 0 18px; letter-spacing: -.01em; }
  .tldr dl { margin: 0; display: grid; gap: 13px; }
  .tldr dt { font-family: var(--font-mono); font-size: .7rem; letter-spacing: .1em; text-transform: uppercase; color: var(--muted); font-weight: 700; margin-bottom: 3px; }
  .tldr dd { margin: 0; color: var(--ink-soft); line-height: 1.6; }
  .tldr dd b { color: var(--ink); font-weight: 600; }
  .grid-3 { display: grid; gap: 16px; grid-template-columns: 1fr; }
  @media (min-width: 680px) { .grid-3 { grid-template-columns: repeat(3, 1fr); } }
  .facet { background: var(--surface); border: 1px solid var(--line); border-radius: 12px; padding: 18px 19px; }
  .facet h3 { font-family: var(--font-mono); font-size: .7rem; letter-spacing: .1em; text-transform: uppercase; color: var(--muted); margin: 0 0 9px; font-weight: 700; }
  .facet p { margin: 0; font-size: .93rem; color: var(--ink-soft); line-height: 1.55; }
  .pipe { display: flex; flex-wrap: wrap; align-items: stretch; gap: 12px; background: var(--surface); border: 1px solid var(--line); border-radius: 14px; padding: 22px 20px; box-shadow: var(--shadow); }
  .lane { display: flex; flex-direction: column; gap: 10px; flex: 1 1 auto; min-width: 0; }
  .lane__label { font-family: var(--font-mono); font-size: .66rem; letter-spacing: .1em; text-transform: uppercase; font-weight: 700; color: var(--phase); display: flex; align-items: center; gap: 6px; }
  .lane__label::before { content:""; width: 8px; height: 8px; border-radius: 2px; background: var(--phase); }
  .lane__nodes { display: flex; flex-wrap: wrap; gap: 7px; }
  .node { display: inline-flex; align-items: center; justify-content: center; min-width: 34px; height: 34px; padding: 0 6px; border-radius: 9px; font-family: var(--font-mono); font-size: .82rem; font-weight: 600; font-variant-numeric: tabular-nums; text-decoration: none; color: var(--phase); background: color-mix(in srgb, var(--phase) 12%, transparent); border: 1px solid color-mix(in srgb, var(--phase) 34%, transparent); }
  .node:hover { background: color-mix(in srgb, var(--phase) 22%, transparent); }
  .lane--setup { flex: 0 0 auto; --phase: var(--setup); }
  .lane--def { --phase: var(--accent); }
  .lane--wire { --phase: var(--wire); }
  .lane--verify { flex: 0 0 auto; --phase: var(--commit); }
  .pipe__arrow { align-self: center; color: var(--muted); font-size: 1.1rem; flex: 0 0 auto; }
  .pipe-note { margin: 12px 2px 0; font-size: .84rem; color: var(--muted); }
  .pipe-note code { font-family: var(--font-mono); font-size: .84em; color: var(--ink-soft); }
  .cons { display: grid; gap: 1px; background: var(--line); border: 1px solid var(--line); border-radius: 12px; overflow: hidden; }
  @media (min-width: 720px) { .cons { grid-template-columns: 1fr 1fr; } }
  .cons > div { background: var(--surface); padding: 15px 18px; }
  .cons dt { font-size: .8rem; font-weight: 700; color: var(--ink); margin: 0 0 4px; }
  .cons dd { margin: 0; font-size: .88rem; color: var(--muted); line-height: 1.5; }
  .cons code { font-family: var(--font-mono); font-size: .82em; color: var(--ink-soft); background: var(--surface-2); padding: 1px 5px; border-radius: 5px; }
  .wave-head { display: flex; align-items: center; gap: 13px; margin: 44px 0 4px; padding-top: 8px; }
  .wave-head .badge { font-family: var(--font-mono); font-size: .72rem; font-weight: 700; letter-spacing: .08em; text-transform: uppercase; padding: 5px 11px; border-radius: 8px; color: var(--ph); background: color-mix(in srgb, var(--ph) 13%, transparent); border: 1px solid color-mix(in srgb, var(--ph) 30%, transparent); }
  .wave-head .desc { font-size: .88rem; color: var(--muted); }
  .wave--def { --ph: var(--accent); } .wave--wire { --ph: var(--wire); } .wave--setup { --ph: var(--setup); } .wave--verify { --ph: var(--commit); }
  .task { background: var(--surface); border: 1px solid var(--line); border-radius: 14px; padding: 24px 26px; margin-top: 16px; box-shadow: var(--shadow); scroll-margin-top: 24px; position: relative; overflow: hidden; }
  .task::before { content: ""; position: absolute; inset: 0 auto 0 0; width: 3px; background: var(--ph, var(--accent)); }
  .task--def { --ph: var(--accent); } .task--wire { --ph: var(--wire); } .task--setup { --ph: var(--setup); } .task--verify { --ph: var(--commit); }
  .task__head { display: flex; gap: 16px; align-items: flex-start; }
  .task__no { font-family: var(--font-mono); font-size: 1.5rem; font-weight: 700; line-height: 1; color: var(--ph); font-variant-numeric: tabular-nums; flex: 0 0 auto; min-width: 2ch; }
  .task__title { margin: 0; }
  .task__title .k { display: block; font-family: var(--font-mono); font-size: .68rem; letter-spacing: .1em; text-transform: uppercase; color: var(--muted); font-weight: 600; margin-bottom: 5px; }
  .task__title h3 { margin: 0; font-size: 1.14rem; font-weight: 700; letter-spacing: -.008em; line-height: 1.35; }
  .task__title h3 code { font-family: var(--font-mono); font-size: .86em; color: var(--ph); }
  .meta { display: grid; gap: 10px; margin: 18px 0 4px; }
  .meta__row { display: flex; gap: 10px; font-size: .86rem; align-items: baseline; }
  .meta__k { font-family: var(--font-mono); font-size: .66rem; letter-spacing: .08em; text-transform: uppercase; color: var(--muted); font-weight: 700; flex: 0 0 74px; padding-top: 2px; }
  .meta__v { color: var(--ink-soft); min-width: 0; }
  .meta__v code, .filepath { font-family: var(--font-mono); font-size: .82em; }
  .filepath { color: var(--ink); background: var(--surface-2); padding: 1px 6px; border-radius: 5px; word-break: break-all; }
  .dep { display: inline-flex; align-items: center; gap: 6px; font-family: var(--font-mono); font-size: .78rem; color: var(--wire); }
  .dep--in { color: var(--accent); }
  .steps { list-style: none; counter-reset: s; margin: 18px 0 0; padding: 0; display: grid; gap: 14px; }
  .steps > li { counter-increment: s; padding-left: 30px; position: relative; font-size: .95rem; color: var(--ink-soft); line-height: 1.6; }
  .steps > li::before { content: counter(s); position: absolute; left: 0; top: 0; font-family: var(--font-mono); font-size: .7rem; font-weight: 700; width: 20px; height: 20px; border-radius: 6px; display: grid; place-items: center; color: var(--muted); background: var(--surface-2); border: 1px solid var(--line); }
  .steps b { color: var(--ink); font-weight: 650; }
  .steps code { font-family: var(--font-mono); font-size: .84em; background: var(--surface-2); padding: 1px 5px; border-radius: 5px; color: var(--ink); }
  .code { position: relative; margin: 12px 0 2px; }
  .code pre { margin: 0; background: var(--surface-2); border: 1px solid var(--line); border-radius: 10px; padding: 16px 18px; overflow-x: auto; }
  .code code { font-family: var(--font-mono); font-size: .82rem; line-height: 1.6; color: var(--ink); white-space: pre; }
  .code__copy { position: absolute; top: 9px; right: 9px; font-family: var(--font-mono); font-size: .68rem; letter-spacing: .04em; text-transform: uppercase; color: var(--muted); background: var(--surface); border: 1px solid var(--line); border-radius: 6px; padding: 3px 8px; cursor: pointer; opacity: 0; transition: opacity .15s; }
  .code:hover .code__copy, .code__copy:focus-visible { opacity: 1; }
  .code__copy:hover { color: var(--ink); border-color: var(--muted); }
  .commit { display: flex; align-items: center; gap: 11px; margin-top: 18px; padding: 11px 14px; border-radius: 9px; background: color-mix(in srgb, var(--commit) 8%, transparent); border: 1px solid color-mix(in srgb, var(--commit) 26%, transparent); }
  .commit .tag { font-family: var(--font-mono); font-size: .64rem; font-weight: 700; letter-spacing: .1em; text-transform: uppercase; color: var(--commit); flex: 0 0 auto; display: inline-flex; align-items: center; gap: 6px; }
  .commit .tag::before { content: "◆"; font-size: .7em; }
  .commit code { font-family: var(--font-mono); font-size: .8rem; color: var(--ink); word-break: break-word; }
  .matrix { width: 100%; border-collapse: collapse; font-size: .86rem; margin-top: 4px; }
  .matrix th, .matrix td { text-align: left; padding: 9px 12px; border-bottom: 1px solid var(--line); white-space: nowrap; }
  .matrix th { font-family: var(--font-mono); font-size: .66rem; letter-spacing: .08em; text-transform: uppercase; color: var(--muted); font-weight: 700; }
  .matrix td code { font-family: var(--font-mono); font-size: .82em; color: var(--ink-soft); }
  .matrix .ok { color: var(--commit); font-weight: 700; }
  .matrix tr td:first-child { font-family: var(--font-mono); color: var(--accent); font-size: .8rem; }
  .matrix-scroll { overflow-x: auto; border: 1px solid var(--line); border-radius: 12px; background: var(--surface); }
  .risk { margin-top: 20px; background: color-mix(in srgb, var(--warn) 8%, transparent); border: 1px solid color-mix(in srgb, var(--warn) 26%, transparent); border-radius: 12px; padding: 18px 20px; }
  .risk h3 { margin: 0 0 12px; font-size: .82rem; font-family: var(--font-mono); letter-spacing: .1em; text-transform: uppercase; color: var(--warn); font-weight: 700; }
  .risk ul { margin: 0; padding-left: 18px; display: grid; gap: 9px; }
  .risk li { font-size: .9rem; color: var(--ink-soft); line-height: 1.55; }
  .risk code { font-family: var(--font-mono); font-size: .84em; color: var(--ink); }
  footer { margin-top: 60px; padding-top: 22px; border-top: 1px solid var(--line); color: var(--muted); font-size: .8rem; display: flex; flex-wrap: wrap; gap: 6px 16px; align-items: center; }
  footer code { font-family: var(--font-mono); font-size: .9em; }
  :focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; border-radius: 4px; }
  a { color: var(--accent); }
</style>
```

## 2. Script — 그대로 인라인

```html
<script>
  var bar = document.getElementById('progress');
  function onScroll() { var h = document.documentElement; var max = h.scrollHeight - h.clientHeight; var pct = max > 0 ? (h.scrollTop || document.body.scrollTop) / max * 100 : 0; bar.style.width = pct + '%'; }
  document.addEventListener('scroll', onScroll, { passive: true }); onScroll();
  var links = Array.prototype.slice.call(document.querySelectorAll('.rail a'));
  var byId = {}; links.forEach(function (a) { byId[a.getAttribute('href').slice(1)] = a; });
  var targets = links.map(function (a) { return document.getElementById(a.getAttribute('href').slice(1)); }).filter(Boolean);
  if ('IntersectionObserver' in window) {
    var spy = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) { if (e.isIntersecting) { links.forEach(function (l) { l.classList.remove('active'); }); var a = byId[e.target.id]; if (a) a.classList.add('active'); } });
    }, { rootMargin: '-20% 0px -70% 0px', threshold: 0 });
    targets.forEach(function (t) { spy.observe(t); });
  }
  document.addEventListener('click', function (e) {
    var btn = e.target.closest('.code__copy'); if (!btn) return;
    var code = btn.parentElement.querySelector('code'); if (!code) return;
    navigator.clipboard.writeText(code.innerText).then(function () { var prev = btn.textContent; btn.textContent = '복사됨'; setTimeout(function () { btn.textContent = prev; }, 1400); });
  });
</script>
```

## 3. 골격 — 항상 이 구조

```html
<div class="progress" id="progress"></div>
<div class="wrap"><div class="doc">
  <aside class="rail" aria-label="내비게이션"> … rail 링크 … </aside>
  <main> … masthead + sections … </main>
</div></div>
```

Rail 링크는 각 섹션/태스크 `id`를 가리킨다. wave가 있으면 `rail__wave` 라벨로 그룹핑, `--dot`으로 단계 색:

```html
<p class="rail__wave" style="--dot: var(--accent)">정의</p>
<a href="#task-1"><span class="n">01</span><span>짧은 라벨</span></a>
```

## 4. 컴포넌트 — 내용 채워 조립

**Masthead** (항상):
```html
<header class="masthead">
  <span class="eyebrow">Implementation Plan</span>  <!-- 또는 Design Spec -->
  <h1>{짧은 제목}</h1>
  <p class="lead">{1~2문장 리드, 핵심어는 <strong>}</p>
  <div class="chips">
    <span class="chip"><b>issue</b><code>HDA-xxxxx</code></span>
    <span class="chip"><b>stack</b>{…}</span>
  </div>
</header>
```

**TL;DR 카드** (TL;DR 섹션 있으면):
```html
<section id="tldr"><div class="sec-head"><span class="kick">01</span><h2>TL;DR</h2></div>
  <div class="tldr">
    <p class="headline">{리드 1문장}</p>
    <dl>
      <div><dt>문제</dt><dd>…</dd></div>
      <div><dt>해결</dt><dd>…</dd></div>
      <div><dt>범위 밖</dt><dd>…</dd></div>
    </dl>
  </div>
</section>
```

**Facet 3-grid** (Goal/Architecture/Tech 또는 spec의 핵심 축):
```html
<div class="grid-3">
  <div class="facet"><h3>Goal</h3><p>…</p></div>
  <div class="facet"><h3>Architecture</h3><p>…</p></div>
  <div class="facet"><h3>{핵심 제약}</h3><p>…</p></div>
</div>
```

**Pipeline** (태스크가 순서/wave/의존성을 가질 때만 — 없으면 생략):
```html
<div class="pipe">
  <div class="lane lane--def"><span class="lane__label">{단계명}</span>
    <div class="lane__nodes"><a class="node" href="#task-1">1</a>…</div></div>
  <span class="pipe__arrow" aria-hidden="true">→</span>
  <div class="lane lane--wire">…</div>
</div>
<p class="pipe-note">{의존성/순서 근거 1문장}</p>
```
lane 변형: `lane--setup`(그레이) · `lane--def`(인디고) · `lane--wire`(틸) · `lane--verify`(그린).

**Constraints grid** (Global Constraints 있으면):
```html
<dl class="cons">
  <div><dt>{라벨}</dt><dd>{설명, 식별자는 <code>}</dd></div> …
</dl>
```

**Wave head + Task card** (작업 항목/Task):
```html
<div class="wave-head wave--def"><span class="badge">Wave A · 정의</span><span class="desc">{모듈/커밋 수}</span></div>

<article class="task task--def" id="task-1">
  <div class="task__head"><span class="task__no">01</span>
    <div class="task__title"><span class="k">{단계 · 모듈}</span><h3>{제목, 식별자는 <code>}</h3></div></div>
  <div class="meta">
    <div class="meta__row"><span class="meta__k">files</span><span class="meta__v"><span class="filepath">경로:라인</span></span></div>
    <div class="meta__row"><span class="meta__k">produces</span><span class="meta__v"><span class="dep">→ Task N 소비</span></span></div>
  </div>
  <ol class="steps">
    <li><b>{요약}</b> — {설명}.
      <div class="code"><button class="code__copy" type="button">복사</button><pre><code>{코드, &lt; &gt; &amp; 이스케이프}</code></pre></div>
    </li>
  </ol>
  <div class="commit"><span class="tag">commit</span><code>{커밋 메시지}</code></div>
</article>
```
task 변형: `task--setup` · `task--def` · `task--wire` · `task--verify`. 소비 의존은 `dep--in`(`← Task N 정의`).

**Coverage matrix** (Self-Review/커버리지 있으면):
```html
<div class="matrix-scroll"><table class="matrix">
  <thead><tr><th>Spec</th><th>항목</th><th>Task</th><th>상태</th></tr></thead>
  <tbody><tr><td>A-1</td><td>…</td><td><code>Task 1</code></td><td class="ok">✓</td></tr></tbody>
</table></div>
```

**Risk box** (미해결/리스크):
```html
<div class="risk"><h3>미해결 · 리스크</h3><ul><li>…</li></ul></div>
```

**Footer** (항상): 문서 종류 · issue · 한 줄 요약.

## 5. 적응 규칙 (하이브리드 핵심)

- **plan**: masthead(`Implementation Plan`) → TL;DR → 구조개요(facet) → 파이프라인(태스크에 wave/의존성 있을 때) → Constraints → 작업 항목(wave+task card, 커밋 게이트) → Self-Review(matrix+risk). 커밋 게이트/파일/의존성을 반드시 노출.
- **spec**: masthead(`Design Spec`) → TL;DR/개요 → 핵심 결정·요구사항·AC를 facet/cons/prose로 → 대안·트레이드오프 → 미해결(risk). **정렬된 태스크가 없으면 태스크 파이프라인·커밋 게이트 생략.** 단 문서에 있는 데이터 흐름·다이어그램은 렌더한다(아래).
- **실행 파이프라인(태스크 흐름)은 정렬된 태스크/의존성이 있을 때만** 그린다. 번호 목록을 강제 스텝으로 과표현하지 않는다.
- **문서에 이미 있는 다이어그램·데이터 흐름은 시각 렌더한다** — `.pipe`/node 스타일을 재사용하되 "실행 파이프라인"이 아니라 문서가 부르는 이름(예: 데이터 흐름)으로 라벨. 태스크 파이프라인 날조와는 별개다.
- **wave 그룹핑은 태스크가 단계로 갈릴 때만**(예: 정의→배선). 아니면 flat task 리스트.
- 단계 색은 의미에 매핑: 준비=setup, 정의/선행=def(인디고), 연결/발화/구현=wire(틸), 검증/커밋=verify(그린).
- 내용은 **실제 문서에서** 가져온다. lorem 금지. 코드블록의 `<` `>` `&`는 반드시 이스케이프.

## 6. Artifact 발행 규약

- `title`: plan = `[plan] {topic}` · spec = `[spec] {topic}`.
- `favicon`: plan 기본 🗺️ · spec 기본 📋. 주제가 뚜렷하면 맞춤(예: 이벤트 로그 📡). 재발행 시 **고정**.
- `description`: 1문장 요약.
- 발행 전 `artifact-design` 스킬은 이 디자인 시스템이 이미 충족 — 순수 재로드 불필요.
- 발행 후 URL을 원본 `.md` 최상단에 `<!-- artifact: {URL} -->`로 기록, 재발행 시 `url=`로 같은 페이지 갱신.
