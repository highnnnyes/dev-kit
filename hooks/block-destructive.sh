#!/usr/bin/env bash
# dev-kit PreToolUse 훅 — 파괴적 명령 하드 게이트 (matcher: Bash|Edit|Write)
#
# 계약 (공식 문서 기준, CLI 2.1.x — code.claude.com/docs/en/hooks):
#   입력  : stdin JSON — .tool_name, .tool_input.command(Bash),
#           .tool_input.file_path(Edit/Write), .cwd
#   출력  : exit 0 + hookSpecificOutput.permissionDecision=deny 로 차단
#           (훅 deny는 settings.json permissions allow보다 우선한다 — 실측·문서 일치)
#   실패시: 무조건 exit 0 (통과) — 훅 오류가 루프를 죽이지 않게 한다
#
# 차단 범주 3종:
#   [되돌리기] **미커밋 작업을 없애거나 워킹트리를 되돌리는 모든 명령.**
#     아래 패턴들은 목록 나열이 아니라 이 범주의 현재 알려진 표면이다 —
#     변종이 나오면 "미커밋 작업이 사라지는가"를 범주 기준으로 판단해 추가한다.
#     근거: 병렬 태스크의 미커밋 산출물을 git checkout <경로>로 파괴한 실사고 (2026-08).
#     오탐 방지: git checkout -b(브랜치 생성)·git checkout <브랜치>(전환)는 허용 —
#     경로 인자가 있는 형태만 차단한다 (워크트리 격리가 브랜치 조작에 의존한다).
#   [데이터 파괴] DROP SCHEMA/DATABASE/TABLE·TRUNCATE·rm -rf 등 데이터·환경을 지우는 명령.
#   [스코프 밖 쓰기] Edit/Write의 file_path가 프로젝트 루트 .dev-kit-scope 목록에
#     없으면 deny. 파일이 없으면 검사를 건너뛴다 (단독 작업·수동 세션 대응).
#     한계: 동시 디스패치된 태스크 **간** 교차는 못 막는다(둘 다 목록에 있으므로) —
#     그 층은 워크트리 격리(B)가 담당한다. README 참조.
#
# 한계: 문자열 매칭이라 .sql 파일 경유·변수 조립·스크립트 래핑으로 우회 가능하다.
# 최종 보증은 DB 권한(harden 스킬 L1)이며 이 훅은 심층방어의 한 겹이다.

set -u

ALLOW_FILE=".dev-kit-allow-destructive"
SCOPE_FILE=".dev-kit-scope"

# --- 입력 파싱 (jq → python3 → 통과) -----------------------------------
INPUT="$(cat 2>/dev/null)" || exit 0
[ -n "$INPUT" ] || exit 0

if command -v jq >/dev/null 2>&1; then
  TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)" || exit 0
  COMMAND="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)" || exit 0
  FILE_PATH="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)" || exit 0
  CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)" || exit 0
elif command -v python3 >/dev/null 2>&1; then
  eval "$(printf '%s' "$INPUT" | python3 -c 'import json,sys,shlex
try:
    d = json.load(sys.stdin)
    ti = d.get("tool_input", {}) or {}
    print("TOOL=%s"      % shlex.quote(d.get("tool_name", "") or ""))
    print("COMMAND=%s"   % shlex.quote(ti.get("command", "") or ""))
    print("FILE_PATH=%s" % shlex.quote(ti.get("file_path", "") or ""))
    print("CWD=%s"       % shlex.quote(d.get("cwd", "") or ""))
except Exception:
    print("TOOL=;COMMAND=;FILE_PATH=;CWD=")' 2>/dev/null)" || exit 0
else
  exit 0   # 파서 없음 — 통과 (fail open)
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-${CWD:-}}"

# --- deny 출력 ----------------------------------------------------------
deny() {
  REASON="$1"
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
  fi
  exit 0
}

# ========================================================================
# [스코프 밖 쓰기] — Edit/Write
# ========================================================================
if [ "${TOOL:-}" = "Edit" ] || [ "${TOOL:-}" = "Write" ]; then
  [ -n "${FILE_PATH:-}" ] || exit 0
  [ -n "$PROJECT_DIR" ] || exit 0
  [ -f "$PROJECT_DIR/$SCOPE_FILE" ] || exit 0   # 스코프 파일 없음 — 검사 생략

  # 스코프 파일 자체는 항상 허용 (오케스트레이터의 생성·갱신이 잠기지 않게)
  case "$FILE_PATH" in
    "$SCOPE_FILE"|*"/$SCOPE_FILE") exit 0 ;;
  esac

  REL="${FILE_PATH#"$PROJECT_DIR"/}"
  while IFS= read -r line || [ -n "$line" ]; do
    line="$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -n "$line" ] || continue
    case "$line" in \#*) continue ;; esac
    # 정확 일치(절대/상대) 또는 접미 일치(워크트리 경로 대응: <wt>/<상대경로>)
    if [ "$FILE_PATH" = "$line" ] || [ "$REL" = "$line" ]; then exit 0; fi
    case "$FILE_PATH" in */"$line") exit 0 ;; esac
  done < "$PROJECT_DIR/$SCOPE_FILE"

  deny "스코프 밖 쓰기 차단 (dev-kit 훅). ${FILE_PATH} 는 현재 디스패치된 태스크의 대상 파일 목록(${SCOPE_FILE})에 없다. 태스크 범위 밖 파일이 정말 필요하면 수정하지 말고 BLOCKED로 보고하라. (루프 밖 수동 작업이 막힌 것이면 사용자가 ${SCOPE_FILE} 을 삭제한다.)"
fi

[ "${TOOL:-}" = "Bash" ] || exit 0
[ -n "${COMMAND:-}" ] || exit 0

# --- 정규화: NORM(소문자+공백 축약) / NORM_CASE(공백 축약만 — -D 등 대소문자 판별용)
NORM="$(printf '%s' "$COMMAND" \
  | tr '[:upper:]' '[:lower:]' \
  | tr '\n\t' '  ' \
  | sed 's/  */ /g')"
NORM_CASE="$(printf '%s' "$COMMAND" | tr '\n\t' '  ' | sed 's/  */ /g')"

# --- 패턴 판정 ----------------------------------------------------------
# MATCHED: 예외 파일에서 참조할 패턴 ID. MATCHED_CAT: 사유 선택 (destroy|revert).
MATCHED=""
MATCHED_CAT="destroy"
m() { MATCHED="$1"; }
mr() { MATCHED="$1"; MATCHED_CAT="revert"; }

# [데이터 파괴] -----------------------------------------------------------
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

# [되돌리기] --------------------------------------------------------------
if [ -z "$MATCHED" ]; then
  if printf '%s' "$NORM" | grep -Eq '(^|[^a-z])git +restore( |$)'; then
    mr "git restore"
  elif printf '%s' "$NORM" | grep -Eq '(^|[^a-z])git +clean( |$)'; then
    mr "git clean"
  elif printf '%s' "$NORM" | grep -Eq '(^|[^a-z])git +stash( |$)' \
    && ! printf '%s' "$NORM" | grep -Eq 'git +stash +(list|show)( |$)'; then
    # stash list/show는 읽기 전용이므로 허용 (push/pop/drop/clear/apply 등은 차단)
    mr "git stash"
  elif printf '%s' "$NORM" | grep -Eq '(^|[^a-z])git +rm( |$)'; then
    mr "git rm"
  elif printf '%s' "$NORM" | grep -Eq '(^|[^a-z])git +reflog +expire( |$)'; then
    mr "git reflog expire"
  elif printf '%s' "$NORM" | grep -Eq '(^|[^a-z])git +branch( |$)' \
    && { printf '%s' "$NORM_CASE" | grep -Eq 'git +branch +.*-[a-zA-Z]*D' \
      || { printf '%s' "$NORM" | grep -Eq '(^| )(--force)( |$)' \
        && printf '%s' "$NORM" | grep -Eq '(^| )(-d|--delete)( |$)'; }; }; then
    # -D(강제 삭제)만 차단. 소문자 -d(머지 확인 삭제)는 허용 — 워크트리 정리가 쓴다.
    mr "git branch -D"
  fi
fi

# git checkout — 경로 인자가 있는 형태만 차단 --------------------------------
# `-b`/`-B`/`--orphan`(생성)·`git checkout <브랜치>`(전환)는 허용해야 한다:
# 워크트리 격리가 브랜치 조작에 의존한다. 판별은 인자 실존 검사로 한다 —
# 인자가 실제 파일/디렉토리로 존재하면 경로 checkout이다. `--` 명시는 무조건 경로다.
# 알려진 한계: 워킹트리에서 이미 삭제된 파일의 경로 checkout(파일이 없어 실존
# 검사를 통과)은 `--` 없이 쓰면 잡지 못한다.
if [ -z "$MATCHED" ]; then
  case "$NORM" in
    *"git checkout"*)
      SEG="$(printf '%s' "$NORM_CASE" | sed -n 's/.*[Gg]it *checkout//p' | sed 's/[;&|].*//')"
      HAS_CREATE=""
      CK=""
      for t in $SEG; do
        case "$t" in
          -b|-B|--orphan|--detach) HAS_CREATE=1 ;;
          --) CK="git checkout <경로>"; break ;;
          -*) : ;;
          *)
            tt="${t%\"}"; tt="${tt#\"}"; tt="${tt%\'}"; tt="${tt#\'}"
            if [ -e "$tt" ] || { [ -n "${CWD:-}" ] && [ -e "$CWD/$tt" ]; }; then
              CK="git checkout <경로>"; break
            fi
            ;;
        esac
      done
      if [ -n "$CK" ] && [ -z "$HAS_CREATE" ]; then
        mr "git checkout <경로>"
      fi
      ;;
  esac
fi

# 문자열 오탐 제외: 단일 `git commit`/`git log`/`echo`처럼 파괴에 도달할 수
# 없는 명령에 패턴이 문자열로 들어간 경우 (예: 커밋 메시지에 "drop table",
# "git checkout 사고"). 파이프·연결(| ; &)이 있으면 실행 경로로 흘려보낼 수
# 있으므로 제외하지 않는다.
case "$MATCHED" in
  "drop schema"|"drop database"|"drop table"|"truncate"|"delete from where 1=1"|\
  "git checkout <경로>"|"git restore"|"git clean"|"git stash"|"git rm"|\
  "git branch -D"|"git reflog expire")
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
if [ -n "$PROJECT_DIR" ] && [ -f "$PROJECT_DIR/$ALLOW_FILE" ]; then
  if grep -v '^[[:space:]]*#' "$PROJECT_DIR/$ALLOW_FILE" 2>/dev/null \
     | grep -Fq "$MATCHED"; then
    echo "dev-kit: 파괴적 명령 예외 적용 — 패턴 '$MATCHED' 이 $ALLOW_FILE 에 허용됨 (명령: $COMMAND)" >&2
    exit 0
  fi
fi

# --- 차단 ---------------------------------------------------------------
if [ "$MATCHED_CAT" = "revert" ]; then
  deny "미커밋 작업을 되돌리는 명령은 에이전트가 실행하지 않는다 (dev-kit 훅 · 패턴: ${MATCHED}). 병렬 태스크의 산출물을 파괴한 사고 사례가 있다(2026-08). 복구가 필요하면 사용자가 직접 수행한다. 이 프로젝트에서 상시 허용해야 하면 ${ALLOW_FILE} 에 '${MATCHED}' 를 적고 사유를 주석으로 남겨라(git 추적 필수)."
else
  deny "파괴적 명령 차단 (dev-kit 훅 · 패턴: ${MATCHED}). 시드·마이그레이션 검증은 스크래치 리소스(별도 DB·리포 사본)에서 수행하라. 정말 필요하면 사용자가 직접 실행한다. 이 프로젝트에서 상시 허용해야 하면 ${ALLOW_FILE} 에 '${MATCHED}' 를 적고 사유를 주석으로 남겨라(git 추적 필수)."
fi
