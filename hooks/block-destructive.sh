#!/usr/bin/env bash
# dev-kit PreToolUse 훅 — 파괴적 Bash 명령 하드 게이트
#
# 계약 (공식 문서 기준, CLI 2.1.x):
#   입력  : stdin JSON — .tool_input.command, .cwd
#   출력  : exit 0 + hookSpecificOutput.permissionDecision=deny 로 차단
#   실패시: 무조건 exit 0 (통과) — 훅 오류가 루프를 죽이지 않게 한다
#
# 한계: 문자열 매칭이라 .sql 파일 경유·변수 조립으로 우회 가능하다.
# 최종 보증은 DB 권한(harden 스킬 L1)이며 이 훅은 심층방어의 한 겹이다.

set -u

ALLOW_FILE=".dev-kit-allow-destructive"

# --- 입력 파싱 (jq → python3 → 통과) -----------------------------------
INPUT="$(cat 2>/dev/null)" || exit 0
[ -n "$INPUT" ] || exit 0

if command -v jq >/dev/null 2>&1; then
  COMMAND="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)" || exit 0
  CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)" || exit 0
elif command -v python3 >/dev/null 2>&1; then
  COMMAND="$(printf '%s' "$INPUT" | python3 -c 'import json,sys
try:
    d = json.load(sys.stdin)
    print(d.get("tool_input", {}).get("command", ""))
except Exception:
    pass' 2>/dev/null)" || exit 0
  CWD="$(printf '%s' "$INPUT" | python3 -c 'import json,sys
try:
    d = json.load(sys.stdin)
    print(d.get("cwd", ""))
except Exception:
    pass' 2>/dev/null)" || exit 0
else
  exit 0   # 파서 없음 — 통과 (fail open)
fi

[ -n "${COMMAND:-}" ] || exit 0

# --- 정규화: 소문자 + 연속공백 축약 -------------------------------------
NORM="$(printf '%s' "$COMMAND" \
  | tr '[:upper:]' '[:lower:]' \
  | tr '\n\t' '  ' \
  | sed 's/  */ /g')"

# --- 패턴 판정 ----------------------------------------------------------
# MATCHED 에는 예외 파일에서 참조할 패턴 ID를 넣는다.
MATCHED=""
m() { MATCHED="$1"; }

case "$NORM" in
  *"drop schema"*)   m "drop schema" ;;
  *"drop database"*) m "drop database" ;;
  *"drop table"*)    m "drop table" ;;
  *dropdb*)          m "dropdb" ;;
  *pg_restore*)      m "pg_restore" ;;
  *"docker volume rm"*) m "docker volume rm" ;;
  *"git reset --hard"*) m "git reset --hard" ;;
esac

if [ -z "$MATCHED" ]; then
  # 정규식이 필요한 패턴들
  if printf '%s' "$NORM" | grep -Eq '(^| |;|&|\|)truncate( |$)'; then
    m "truncate"
  elif printf '%s' "$NORM" | grep -Eq 'delete +from .* where +1 *= *1'; then
    m "delete from where 1=1"
  elif printf '%s' "$NORM" | grep -Eq '(docker +compose|docker-compose)( +[a-z-]+)* +down' \
     && printf '%s' "$NORM" | grep -Eq '(^| )(-v|--volumes)( |$)'; then
    m "docker compose down -v"
  elif printf '%s' "$NORM" | grep -Eq 'rm +(-[a-z-]* )*-([a-z]*r[a-z]*f|[a-z]*f[a-z]*r)' \
     || printf '%s' "$NORM" | grep -Eq 'rm +.*--recursive.*--force|rm +.*--force.*--recursive'; then
    m "rm -rf"
  elif printf '%s' "$NORM" | grep -Eq 'git +push( +[^ ]+)* +(-f|--force[a-z-]*)( |$)'; then
    m "git push --force"
  fi
fi

# SQL 문자열 오탐 제외: 단일 `git commit`/`git log`/`echo`처럼 DB에 도달할 수
# 없는 명령에 SQL 키워드가 문자열로 들어간 경우 (예: 커밋 메시지에 "drop table").
# 파이프·연결(| ; && ||)이 있으면 DB 클라이언트로 흘려보낼 수 있으므로 제외하지 않는다.
case "$MATCHED" in
  "drop schema"|"drop database"|"drop table"|"truncate"|"delete from where 1=1")
    if ! printf '%s' "$NORM" | grep -Eq '[|;&]'; then
      case "$NORM" in
        "git commit "*|"git log "*|"git tag "*|"echo "*|"printf "*)
          MATCHED="" ;;
      esac
    fi
    ;;
esac

[ -n "$MATCHED" ] || exit 0   # 해당 없음 — 통과

# --- 프로젝트 예외 경로 --------------------------------------------------
# 프로젝트 루트의 .dev-kit-allow-destructive 에 패턴 ID가 명시돼 있으면 통과.
# 이 파일은 git 추적 대상이어야 한다 (.gitignore 금지 — 리뷰 가능해야 함).
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-${CWD:-}}"
if [ -n "$PROJECT_DIR" ] && [ -f "$PROJECT_DIR/$ALLOW_FILE" ]; then
  if grep -v '^[[:space:]]*#' "$PROJECT_DIR/$ALLOW_FILE" 2>/dev/null \
     | grep -Fq "$MATCHED"; then
    echo "dev-kit: 파괴적 명령 예외 적용 — 패턴 '$MATCHED' 이 $ALLOW_FILE 에 허용됨 (명령: $COMMAND)" >&2
    exit 0
  fi
fi

# --- 차단 ---------------------------------------------------------------
REASON="파괴적 명령 차단 (dev-kit 훅 · 패턴: ${MATCHED}). 시드·마이그레이션 검증은 스크래치 리소스(별도 DB·리포 사본)에서 수행하라. 정말 필요하면 사용자가 직접 실행한다. 이 프로젝트에서 상시 허용해야 하면 ${ALLOW_FILE} 에 '${MATCHED}' 를 적고 사유를 주석으로 남겨라(git 추적 필수)."

if command -v jq >/dev/null 2>&1; then
  jq -n --arg reason "$REASON" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
elif command -v python3 >/dev/null 2>&1; then
  REASON="$REASON" python3 -c 'import json, os
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": os.environ["REASON"],
    }
}))'
else
  exit 0
fi

exit 0
