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
- PLAN.md 형식(stage/task, verify, role, tier, [P], DECISIONS)
  ↔ execute-plan이 읽는 필드
- builder/builder-light 출력(STATUS·CHANGED·VERIFY·NOTES·BLOCKED,
  red→green 기록) ↔ execute-plan·reviewer가 소비하는 필드
- reviewer 출력(VERDICT·BLOCKING·NON-BLOCKING·VERIFIED·NEXT TASK의
  role·tier·P그룹) ↔ 소비처
- stage-reviewer 출력(STAGE VERDICT·FINDINGS·PROPOSED TASKS) ↔ 소비처

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
