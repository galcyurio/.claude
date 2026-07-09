#!/usr/bin/env bash
# merge-develop — develop 최신 변경을 epic base(feature-base/HDA-xxxx)에 반영한다.
#
# 브랜치 생성 → develop 머지 → push → 자동 생성 PR 감지 → CI Check 완료 대기 → 보고.
# auto면 CI 통과 시 approve → auto-merge 발동 → 실제 머지 완료까지 대기 → 보고.
# 충돌만 사람이 푼다(자동 해결 안 함).
#
# PR은 merge/* push를 감지한 create_merge_pr.yml workflow가 만든다(작성자=CI 토큰이라
# 개발자 approve는 셀프 승인이 아니다). auto-merge도 workflow가 켠다.
#
# 리포 안에서 실행한다(gh가 origin으로 리포 자동 감지). git·gh(로그인)만 있으면 단독 실행 가능.
# exit: 0 성공 · 1 실패 · 2 사용법/사전조건 · 3 머지 충돌(사람 해결) · 4 gh 인증 · 124 타임아웃

set -uo pipefail

usage() {
  cat <<'EOF'
merge-develop — develop 최신 변경을 epic base(feature-base/HDA-xxxx)에 반영

사용법:
  merge-develop.sh <feature-base 브랜치 | HDA-키> [auto] [--continue]
  merge-develop.sh -h | --help

  auto        CI 통과 시 approve → auto-merge → 실제 머지 완료까지 대기
  --continue  머지 충돌 해결(git add·commit) 후 push부터 재개

예:
  merge-develop.sh feature-base/HDA-21936-market-marketing
  merge-develop.sh HDA-21936 auto
  merge-develop.sh feature-base/HDA-21936-market-marketing auto --continue
EOF
}

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

# 대기 상한(초)
PR_WAIT=180        # PR 자동 생성 대기
REG_WAIT=120       # CI Check 등록 대기
CHECKS_WAIT=3600   # CI Check 완료 대기 (Android CI는 길다)
MERGE_WAIT=1800    # auto-merge 실제 머지 대기

now() { date +%s; }

# ── 인자 파싱 (순서 자유) ──
MODE=basic; CONTINUE=0; TARGET=""
for a in "$@"; do
  case "$a" in
    -h|--help)  usage; exit 0 ;;
    auto)       MODE=auto ;;
    --continue) CONTINUE=1 ;;
    -*)         echo "알 수 없는 옵션: $a" >&2; exit 2 ;;
    *)          if [ -z "$TARGET" ]; then TARGET="$a"; else echo "인자 과다: $a" >&2; exit 2; fi ;;
  esac
done
[ -n "$TARGET" ] || { usage >&2; exit 2; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "git 리포 안에서 실행하라" >&2; exit 2; }

git fetch origin --prune

# ── base / merge 브랜치 결정 ──
if [ "$CONTINUE" -eq 1 ]; then
  CUR=$(git rev-parse --abbrev-ref HEAD)
  case "$CUR" in
    merge/*) MERGE="$CUR"; BASE="feature-base/${MERGE#merge/}" ;;
    *) echo "--continue는 merge/ 브랜치에서 실행하라 (현재: $CUR)" >&2; exit 2 ;;
  esac
else
  case "$TARGET" in
    feature-base/*) BASE="$TARGET" ;;
    *)  # HDA-키 → origin/feature-base/<키> 정확 일치 or <키>- 접두 (더 긴 키 오매칭 방지)
        CANDS=()
        while IFS= read -r line; do [ -n "$line" ] && CANDS+=("$line"); done < <(
          git branch -r --format='%(refname:short)' \
            | sed -n 's#^origin/##p' \
            | grep -E "^feature-base/${TARGET}(-|$)" || true )
        if   [ "${#CANDS[@]}" -eq 1 ]; then BASE="${CANDS[0]}"
        elif [ "${#CANDS[@]}" -eq 0 ]; then echo "feature-base 브랜치를 못 찾음: $TARGET" >&2; exit 2
        else echo "여러 base 후보 — 정확한 브랜치명을 넘겨라:" >&2; printf '  %s\n' "${CANDS[@]}" >&2; exit 2
        fi ;;
  esac
  MERGE="merge/${BASE#feature-base/}"
fi
echo "base : $BASE"
echo "merge: $MERGE"

GITDIR=$(git rev-parse --git-dir)

# ── 1) merge 브랜치 생성 + develop 머지 (또는 --continue 재개) ──
if [ "$CONTINUE" -eq 0 ]; then
  [ -f "$GITDIR/MERGE_HEAD" ] && { echo "진행 중인 머지가 있다. git commit 또는 git merge --abort 후 재시도" >&2; exit 2; }
  [ -z "$(git status --porcelain)" ] || { echo "working tree가 dirty하다. stash/commit 후 재시도" >&2; exit 2; }
  git show-ref --verify --quiet "refs/remotes/origin/$BASE" || { echo "origin/$BASE 없음" >&2; exit 2; }
  git show-ref --verify --quiet "refs/heads/$MERGE" && { echo "로컬 $MERGE 이미 존재. 정리하거나 --continue로 재개하라" >&2; exit 2; }

  git switch --create "$MERGE" "origin/$BASE"       # stale 로컬 base 아닌 origin tip 기준

  if ! git merge --no-edit "origin/develop"; then   # rebase/squash 아님 — merge commit 보존
    {
      echo ""
      echo "!! develop 머지 충돌 — 자동 해결하지 않는다. 충돌 파일:"
      git diff --name-only --diff-filter=U | sed 's/^/    /'
      echo ""
      echo "해결: 충돌 수정 → git add <파일> → git commit → 아래로 재개:"
      if [ "$MODE" = auto ]; then echo "    $SELF $BASE auto --continue"; else echo "    $SELF $BASE --continue"; fi
      echo "  (되돌리기: git merge --abort)"
    } >&2
    exit 3
  fi
else
  [ -f "$GITDIR/MERGE_HEAD" ] && { echo "머지가 아직 커밋되지 않음. 충돌 해결 후 git commit하고 재실행" >&2; exit 2; }
  [ -z "$(git status --porcelain)" ] || { echo "working tree가 dirty하다. 정리 후 재실행" >&2; exit 2; }
fi

# ── 2) push (base 직접/force push 안 함) → workflow가 PR·auto-merge 생성 ──
git push --set-upstream origin "$MERGE" || { echo "push 실패 — 원격 브랜치/인증/네트워크 확인" >&2; exit 1; }

# ── 3) 자동 생성 PR 감지 (생성 지연 대비 폴링) ──
end=$(( $(now) + PR_WAIT ))
while :; do
  PR=$(gh pr list --head "$MERGE" --state open --json number -q '.[0].number // empty') \
    || { echo "gh pr list 실패 (인증/네트워크)" >&2; exit 4; }
  [ -n "$PR" ] && break
  if [ "$(now)" -ge "$end" ]; then
    echo "PR이 ${PR_WAIT}s 안에 생성되지 않음 (head=$MERGE)" >&2
    echo "  workflow 확인: gh run list --workflow=create_merge_pr.yml" >&2
    exit 1
  fi
  sleep 10
done
URL=$(gh pr view "$PR" --json url -q .url)
echo "PR 감지: #$PR  $URL"

# ── 4) CI Check 등록 대기 (no-checks rc1 오탐 방지 게이트) ──
# gh 일시 실패(빈 출력)를 정수 비교에 넣지 않도록 값을 분리 캡처한다.
end=$(( $(now) + REG_WAIT )); NO_CHECKS=0
while :; do
  n=$(gh pr view "$PR" --json statusCheckRollup -q '.statusCheckRollup | length' 2>/dev/null)
  [ -n "$n" ] && [ "$n" -gt 0 ] && break
  if [ "$(now)" -ge "$end" ]; then NO_CHECKS=1; break; fi
  sleep 10
done

# ── 5) CI Check 완료 대기 + pass/fail 판정 (rc: 0 pass · 8 pending · 1 fail) ──
CHECKS=none
if [ "$NO_CHECKS" -eq 0 ]; then
  end=$(( $(now) + CHECKS_WAIT ))
  while :; do
    gh pr checks "$PR" >/dev/null 2>&1; rc=$?
    case $rc in
      0) CHECKS=pass; break ;;
      8) : ;;                    # pending → 계속 폴링
      1) CHECKS=fail; break ;;   # 등록된 체크가 있는데 rc1 = 실패
      4) echo "gh 인증 필요: gh auth login" >&2; exit 4 ;;
      *) echo "gh 오류 rc=$rc" >&2; exit "$rc" ;;
    esac
    if [ "$(now)" -ge "$end" ]; then CHECKS=timeout; break; fi
    sleep 20
  done
fi

echo "── CI Check 결과 ──"
gh pr checks "$PR" || true
case $CHECKS in
  pass)    echo "결과: 모든 CI Check 통과 (#$PR)" ;;
  fail)    echo "결과: CI 실패 (#$PR)"; [ "$MODE" = auto ] && echo "  → auto-merge 미발동"; exit 1 ;;
  timeout) echo "결과: 체크 완료 대기 ${CHECKS_WAIT}s 초과 (#$PR)"; exit 124 ;;
  none)    echo "결과: 설정된 CI Check 없음 — 대기 대상 없음 (#$PR)" ;;
esac

# ── 6) basic 종료 / auto는 CI 통과 후 approve → 실제 머지까지 대기 ──
if [ "$MODE" != auto ]; then
  echo "완료. approve하면 auto-merge됩니다: $URL"
  exit 0
fi

# 여기 도달 시 CHECKS ∈ {pass, none} (fail→exit1·timeout→exit124). CI 통과 후 approve해 auto-merge를 발동한다.
am=$(gh pr view "$PR" --json autoMergeRequest -q '.autoMergeRequest.mergeMethod // "OFF"')
echo "auto-merge: $am"
[ "$am" = OFF ] && echo "경고: workflow가 auto-merge를 켜지 않음 — 스스로 머지되지 않을 수 있다" >&2
if gh pr review "$PR" --approve -b "develop 최신화 CI 통과 auto-merge 승인"; then
  echo "approve 완료"
else
  echo "경고: approve 실패 (이미 승인했거나 권한 없음)" >&2
fi

end=$(( $(now) + MERGE_WAIT ))
while :; do
  state="$(gh pr view "$PR" --json state -q '.state')"
  [ "$state" = MERGED ] && { echo "머지 완료: #$PR  $URL"; exit 0; }
  [ "$state" = CLOSED ] && { echo "머지 없이 CLOSED: #$PR" >&2; exit 1; }
  if [ "$(now)" -ge "$end" ]; then
    MSS=$(gh pr view "$PR" --json mergeStateStatus -q .mergeStateStatus)
    echo "${MERGE_WAIT}s 내 미머지 (#$PR, state=$state, mergeStateStatus=$MSS)" >&2
    echo "  BLOCKED=필수 리뷰/CODEOWNERS · BEHIND=base 최신화 필요 · DIRTY=충돌 · UNSTABLE=필수 아닌 체크 red" >&2
    exit 1
  fi
  sleep 15
done
