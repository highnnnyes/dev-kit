---
name: audit
description: dev-kit 리포 자체의 정합성 감사. plugin.json version을 올리기 전, 여러 파일을 동시에 수정한 뒤, 또는 사용자가 "감사"를 요청할 때 사용. 읽기 전용 — 보고만 하고 수정하지 않는다.
---

# Audit — dev-kit 자체 감사

분류: **[엄격]** — 검사 항목 A~G를 전부 수행한다. 발견이 없어도 "검사했음"을
남긴다. **읽기 전용** — 수정은 보고 후 사용자 승인 대기.

## 검사 절차

### A) 인벤토리
전 파일 경로 + 줄 수, plugin.json name/version.

### B) 참조 정합성
- 헌법·커맨드·스킬의 라우팅이 언급하는 커맨드/에이전트/스킬이 실재하는가
- 어디서도 참조되지 않는 고아 파일은 없는가
- 예외: 헌법 §7 gstack은 **외부 조건부 참조**이므로 깨진 참조로 판정하지
  않는다 — 조건 가드("설치되어 있지 않으면 무시") 존재만 확인한다.

### C) 계약 일치 (생산 ↔ 소비)
- PLAN.md 형식(stage/task, verify, role, tier, risk, [P], DECISIONS)
  ↔ execute-plan이 읽는 필드 (risk: high → reviewer 사전 승격 라우팅)
- builder/builder-light 출력(STATUS·CHANGED·VERIFY·NOTES·BLOCKED,
  red→green 기록) ↔ execute-plan·reviewer가 소비하는 필드
- reviewer 출력(VERDICT·BLOCKING·NON-BLOCKING·요구사항 추적표·VERIFIED의
  실행 명령 전량·NEXT TASK의 role·tier·risk·P그룹) ↔ 소비처
  (VERIFIED 명령 목록 ↔ PROGRESS.md `- 리뷰명령:` 전재)
- stage-reviewer 출력(STAGE VERDICT·FINDINGS·PROPOSED TASKS·VERIFIED의
  실행 명령 전량) ↔ 소비처
- 직접 처리 태스크 표기(`builder=by=orchestrator`) ↔ stage-reviewer 생략
  조건 판정(직접 처리 1건 이상이면 생략 무효)
- 신규 파일 스코프 확보(`git add -N` CHANGED 한정) ↔ 헌법 §4 기본 검증
  루프와 execute-plan 양쪽에 있는가
- builder/builder-light 출력 `DESTRUCTIVE` 행 ↔ reviewer 검사 항목 ↔
  execute-plan PROGRESS `- 파괴적명령:` 전재 (생산·감사·기록 3자 일치)
- 훅: `hooks/hooks.json`이 실재하고 **PreToolUse(block-destructive.sh,
  matcher Bash|Edit|Write)·PreCompact(precompact-resume.sh) 양쪽**이 등록돼
  있는가, 스크립트 경로(`${CLAUDE_PLUGIN_ROOT}` 기준)·실행 권한이 맞는가,
  README의 차단 패턴 목록(되돌리기 범주 포함)이 스크립트 실제 패턴과
  일치하는가, fail open(exit 0)이 유지되는가
- `.dev-kit-scope` 생산(execute-plan: 디스패치 직전 생성·반환 직후 삭제)
  ↔ 소비(훅의 Edit/Write 스코프 검사) — 파일명·형식(한 줄에 경로 하나)이
  양쪽에서 일치하는가
- `worktree:` 선언(shared-env|isolated-env|off) ↔ execute-plan 병렬 라우팅
  ↔ off/선언 없음 시 순차 강등 폴백 ↔ 헌법 §4 요약 — 값 이름이 일치하는가
- B-5 머지 후 통합 검증 게이트(그룹 머지 직후 verify 재실행, 그룹 크기 1
  생략) ↔ PROGRESS `Group <id> 머지 후 통합검증` 기록 형식
- `Stage N 시작 — base=<sha>` 기록(execute-plan) ↔ stage-reviewer 통합 diff
  스코프(`<시작 sha>..HEAD`) ↔ PreCompact 훅의 base sha 추출 패턴
- RESUME 블록 생산 2원(execute-plan stage 경계·중단 시 ↔ PreCompact 훅) —
  형식(`## RESUME` + 5개 필드)이 일치하는가, 재개 절차(사전 체크 2)가
  이 블록을 읽도록 돼 있는가
- harden 스킬 ↔ 헌법 §4 라우팅 항목 ↔ write-plan Stage 1 harden 태스크
  규정(HARDENING.md 부재 검사)이 서로를 가리키는가

### D) 규칙 충돌
- 중단 조건 목록·검증 루프 규칙·라우팅 번호 참조가 헌법/커맨드/README에서
  일치하는가
- TDD·debugging·Iron Law가 중복 선언 없이 참조 관계로 정리돼 있는가

### E) 에이전트 권한·비용
- reviewer/stage-reviewer는 읽기 전용 tools인가
- builder류 tools 제한이 유지되는가
- 각 에이전트에 model 필드가 있는가 (유효한 별칭/모델 ID인가)
- **티어링 실측**: PROGRESS.md의 model= 라인은 자기보고라 회귀를 못 잡는다.
  티어링 회귀가 의심되면(비용 급증, 품질 급변) 각 에이전트를 1회 호출해
  "You are powered by" 문구로 실제 투입 모델을 확인하는 절차를 안내한다.

### F) 스킬 연동
- 라우팅 ↔ 스킬 핸드오프가 양방향으로 맞물리는가
- docs 스킬 drift 스캔 표에 프로젝트 CLAUDE.md가 포함되는가
- 각 스킬에 [엄격/유연] 분류 표기가 있는가

### G) README 정확성
- 문서에만 있는 기능 / 구현에만 있는 기능

## 출력 형식
1. 인벤토리 표
2. 발견 — 심각도별 **[BLOCKING]** / **[WARNING]** / **[NOTE]**,
   각 항목: `위치(파일:줄) — 문제 — 제안`
3. 한 줄 판정
4. 수정은 승인 대기 — 이 스킬은 고치지 않는다.
