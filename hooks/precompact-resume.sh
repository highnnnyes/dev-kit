#!/usr/bin/env bash
# dev-kit PreCompact 훅 — 컨텍스트 압축 직전 RESUME 블록 flush
#
# 계약 (공식 문서 기준, CLI 2.1.x — code.claude.com/docs/en/hooks):
#   입력: stdin JSON — .cwd, .trigger(auto|manual). PreCompact는 컨텍스트 주입이
#   불가능하고 부수 효과만 가능하다 — 그래서 디스크(PROGRESS.md)로 flush한다.
#   실패시: 무조건 exit 0 — 훅 오류가 압축·루프를 막지 않게 한다.
#
# 동작: 프로젝트에 PLAN.md + PROGRESS.md가 있으면(= dev-kit 루프 프로젝트),
# PROGRESS.md 최상단의 기존 RESUME 블록을 제거하고 새 블록을 prepend한다.
# 셸에서 기계적으로 수집 가능한 필드만 채운다 — 오케스트레이터가 stage 경계에
# 쓰는 RESUME 블록(execute-plan)이 1차 수단이고, 이 훅은 압축으로 컨텍스트를
# 잃기 전 마지막 안전망이다.

set -u

INPUT="$(cat 2>/dev/null)" || exit 0

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$PROJECT_DIR" ]; then
  if command -v jq >/dev/null 2>&1; then
    PROJECT_DIR="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)" || exit 0
  elif command -v python3 >/dev/null 2>&1; then
    PROJECT_DIR="$(printf '%s' "$INPUT" | python3 -c 'import json,sys
try:
    print(json.load(sys.stdin).get("cwd", ""))
except Exception:
    pass' 2>/dev/null)" || exit 0
  fi
fi
[ -n "$PROJECT_DIR" ] || exit 0
cd "$PROJECT_DIR" 2>/dev/null || exit 0
[ -f PLAN.md ] && [ -f PROGRESS.md ] || exit 0   # dev-kit 루프 프로젝트가 아님

TS="$(date '+%Y-%m-%d %H:%M' 2>/dev/null)" || TS="?"

# 기계적 수집 (전부 실패 허용)
# DECISIONS 섹션의 체크박스를 태스크로 오인하지 않도록 Stage 헤딩 이후만 본다
NEXT_TASK="$(awk '/^## Stage/{s=1} s && /^- \[ \]/{sub(/^- \[ \] */,""); print; exit}' PLAN.md 2>/dev/null)"
[ -n "$NEXT_TASK" ] || NEXT_TASK="(PLAN.md에 미완료 태스크 없음)"

OPEN_DECISIONS="$(sed -n '/^## DECISIONS/,/^## /p' PLAN.md 2>/dev/null \
  | grep -E '^- \[ \]' | sed 's/^- \[ \] *//' | tr '\n' ';' | sed 's/;$//')"
[ -n "$OPEN_DECISIONS" ] || OPEN_DECISIONS="없음"

BASE_SHA="$(grep -E 'Stage .* 시작 — base=' PROGRESS.md 2>/dev/null \
  | tail -1 | sed -n 's/.*base=\([0-9a-fA-F][0-9a-fA-F]*\).*/\1/p')"
[ -n "$BASE_SHA" ] || BASE_SHA="기록 없음"

LAST_SHA="$(git rev-parse --short HEAD 2>/dev/null)" || LAST_SHA="?"

MAIN_TREE="$(git rev-parse --show-toplevel 2>/dev/null)"
WORKTREES="$(git worktree list --porcelain 2>/dev/null \
  | sed -n 's/^worktree //p' | grep -v "^${MAIN_TREE}\$" | tr '\n' ' ')"
[ -n "$WORKTREES" ] || WORKTREES="없음"

NB_COUNT="$(grep -c '^- 넘김:' PROGRESS.md 2>/dev/null)" || NB_COUNT="?"

TMP="$(mktemp 2>/dev/null)" || exit 0
{
  printf '## RESUME [%s] (PreCompact 자동 flush)\n' "$TS"
  printf -- '- 다음 태스크: %s\n' "$NEXT_TASK"
  printf -- '- 미해결 DECISIONS: %s\n' "$OPEN_DECISIONS"
  printf -- '- 누적 NON-BLOCKING: PROGRESS.md `- 넘김:` 줄 %s건 참조\n' "$NB_COUNT"
  printf -- '- stage base sha: %s · 남은 워크트리: %s\n' "$BASE_SHA" "$WORKTREES"
  printf -- '- 마지막 커밋 sha: %s\n' "$LAST_SHA"
  printf '\n'
  # 기존 RESUME 블록(어디 있든)은 제거 — 최신 블록 하나만 유지
  awk 'BEGIN{skip=0}
       /^## RESUME/{skip=1; next}
       skip && /^## /{skip=0}
       !skip{print}' PROGRESS.md 2>/dev/null
} > "$TMP" 2>/dev/null && mv "$TMP" PROGRESS.md 2>/dev/null

exit 0
