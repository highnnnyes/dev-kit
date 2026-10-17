#!/usr/bin/env bash
# hooks/block-destructive.sh 입력→기대(차단/통과) 표 — v1.16.1 (dev-kit journal 2026-10-17 확인).
# 훅에 stdin JSON을 넣어 permissionDecision만 본다. 실제 DB·git 명령은 실행하지 않는다.
# 사용: bash hooks/test-block-destructive.sh [훅 경로]   → 실패 0이면 exit 0.
# 표를 바꾸려면 journal에 결정을 남기고 이 파일의 기대 열을 고친다 — 차단 범위가 줄어드는
# 변경은 사용자 확인이 먼저다 (dev-kit CLAUDE.md 수정 규칙).
HOOK="${1:-$(cd "$(dirname "$0")" && pwd)/block-destructive.sh}"
PASS_N=0; FAIL_N=0
t() {  # t <기대 DENY|PASS> <라벨> <명령>
  expect="$1"; label="$2"; cmd="$3"
  out="$(printf '%s' "$cmd" | python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.stdin.read()},"cwd":"/tmp/dev-kit-hooktest-nonexistent"}))' | bash "$HOOK" 2>/dev/null)"
  if printf '%s' "$out" | grep -q '"deny"'; then got=DENY; else got=PASS; fi
  if [ "$got" = "$expect" ]; then PASS_N=$((PASS_N+1)); mark=ok; else FAIL_N=$((FAIL_N+1)); mark=FAIL; fi
  printf '%-4s | 기대 %-4s 실제 %-4s | %s | %s\n' "$mark" "$expect" "$got" "$label" "$(printf '%s' "$cmd" | tr '\n' '⏎' | cut -c1-80)"
}
# 이 스크립트를 실행하는 명령줄(`bash hooks/test-block-destructive.sh`)에는 패턴이 없어야 훅에
# 막히지 않는다. 패턴 문자열은 아래처럼 조립한다.
D='DROP'; d='drop'

echo "--- 오탐 (통과) — 진단 §7-7 2건 + 같은 부류 ---"
t PASS "P3-1 히어독 문서 append" "cat >> docs/diagnosis-2026-10.md <<'EOF'
문구에 \"${D} SCHEMA\"라는 글자가 들어 있자 훅이 막았다.
EOF"
t PASS "P3-2 grep 검색어" 'grep -rn "pg_restore" hooks/ docs/'
t PASS "grep drop table" "grep -n '${d} table' hooks/block-destructive.sh"
t PASS "sed 패턴" "sed -n '/${d} table/p' hooks/block-destructive.sh"
t PASS "rg truncate" 'rg "truncate" docs/'
t PASS "awk 패턴" "awk '/flyway clean/{print}' README.md"
t PASS "git log --grep" "git log --grep='pg_restore' --oneline"
t PASS "python print" "python3 -c \"print('${d} table')\""
t PASS "echo 단독" "echo \"${d} schema x\""
t PASS "printf 단독" "printf '%s\n' 'truncate users'"
t PASS "git commit 메시지" "git commit -m \"fix: ${d} table guard\""
t PASS "git commit && git push" "git commit -m \"docs: ${d} schema 오탐\" && git push"
t PASS "cat 파일 | head" 'cat docs/review-2026-10-16.md | head -50'
t PASS "히어독 → .sql 파일 (실행 없음 — 회색, 파일 경유는 알려진 한계)" "cat > m.sql <<EOF
${D} TABLE users;
EOF"
t PASS "git commit 메시지에 git stash (되돌리기 제외 유지)" 'git commit -m "docs: git stash 사고 기록"'

echo "--- 실제 파괴 (차단 유지) ---"
t DENY "psql -c drop schema" "psql -U app -c \"${D} SCHEMA public CASCADE\""
t DENY "psql drop table" "psql -c \"${d} table users\""
t DENY "mysql drop database" "mysql -u root -e \"${D} DATABASE app\""
t DENY "sqlite3 drop table" "sqlite3 app.db \"${D} TABLE users\""
t DENY "docker exec psql" "docker exec db psql -U app -c \"${d} table users\""
t DENY "docker compose exec psql" "docker compose exec db psql -c \"${d} schema s cascade\""
t DENY "ssh + docker exec psql" "ssh user@host \"docker exec c psql -U a -c '${d} table users'\""
t DENY "psql delete 1=1" 'psql -c "DELETE FROM users WHERE 1=1"'
t DENY "flyway clean" 'flyway clean'
t DENY "flyway -url clean" 'flyway -url=jdbc:postgresql://x/y clean'
t DENY "gradlew flywayClean" './gradlew flywayClean'
t DENY "dropdb" 'dropdb mydb'
t DENY "sudo dropdb" 'sudo -u postgres dropdb mydb'
t DENY "docker exec dropdb" 'docker exec db dropdb -U app mydb'
t DENY "pg_restore --clean" 'pg_restore -d mydb --clean backup.dump'
t DENY "cd && pg_restore (줄바꿈 선두)" 'cd /tmp
pg_restore -d mydb x.dump'
t DENY "coreutils truncate 선두 (현행 유지)" 'truncate -s 0 app.log'
t DENY "docker volume rm" 'docker volume rm app_pgdata'
t DENY "docker compose down -v" 'docker compose down -v'
t DENY "rm -rf" 'rm -rf build/'
t DENY "git reset --hard" 'git reset --hard HEAD~1'
t DENY "git push --force" 'git push --force origin main'
t DENY "git restore" 'git restore src/a.py'
t DENY "git clean" 'git clean -fd'
t DENY "git stash" 'git stash'

echo "--- 결함 수정 (현행 PASS → 차단) ---"
t DENY "psql -c TRUNCATE (따옴표 뒤)" 'psql -c "TRUNCATE users"'
t DENY "git commit && psql truncate" 'git commit -m ok && psql -c "truncate users"'
t DENY "mvn flyway:clean" 'mvn flyway:clean'

echo "--- 우회 시도 (차단) ---"
t DENY "echo | psql" "echo \"${d} schema x cascade\" | psql mydb"
t DENY "히어독 | psql" "psql mydb <<EOF
${D} TABLE users;
EOF"
t DENY "printf | mysql" "printf '${D} DATABASE app' | mysql -u root"
t DENY "echo ; psql" "echo hi; psql -c \"${d} table x\""
t DENY "sh -c psql" "sh -c 'psql -c \"${d} table users\"'"
t DENY "echo > .sql && psql -f" "echo '${D} TABLE users' > m.sql && psql -f m.sql"
t DENY "python subprocess psql" "python3 -c \"import subprocess; subprocess.run(['psql','-c','${D} TABLE users'])\""
t DENY "변수 조립 + psql (문자열이 같은 명령줄에)" "CMD=\"${d} table x\"; psql -c \"\$CMD\""

echo "--- 회색 지대 (현행 판정 기록 — 내용이 안 보이는 형태는 harden L1 몫) ---"
t PASS "psql -f m.sql" 'psql -f m.sql'
t PASS "cat drop.sql | psql" 'cat drop.sql | psql mydb'
t PASS "npm run db:reset" 'npm run db:reset'
t PASS "prisma migrate reset" 'npx prisma migrate reset'
t DENY "grep 검색어에 실행기+패턴 (안전 측 오탐 잔존)" "grep -rn \"psql.*${d} table\" docs/"

echo
echo "결과: 통과 $PASS_N · 실패 $FAIL_N"
[ "$FAIL_N" -eq 0 ]
