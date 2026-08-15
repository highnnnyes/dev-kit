# dev-kit

계획 기반 자율 개발 루프 플러그인. 기능 요청 하나를 던지면 계획 수립 →
태스크 단위 구현 → 독립 검증 → 기록까지 사용자 개입 없이 진행한다.

세 소스의 원칙을 결합해 설계했다:
- **Karpathy 4원칙** — 추측 금지, 최소 코드, 요청 밖 코드 불가침, 검증 가능한 목표
- **리눅스 커널 AI 정책** — 모든 라인의 책임은 인간에게, AI slop 금지, 감사 추적
- **gstack / Superpowers 패턴** — Think→Plan→Build→Review→Test→Ship,
  태스크당 신선한 서브에이전트, 독립 컨텍스트 리뷰

---

## 아키텍처

```
사용자 요청
   ↓
[자동 라우팅 — dev/CLAUDE.md]         ← 커맨드 없이도 요청을 분류해 절차 시작
   ↓
(요구사항 모호 시) brainstorming ──→ DESIGN.md   ← 질문으로 설계 확정
   ↓        (대형/고위험 시) grill: 설계/계획 심문
/write-plan ──→ PLAN.md               ← stage → verify 하나 단위 태스크, role/tier/risk 태그, [P]병렬 그룹
   ↓ (DECISIONS 없으면 대기 없이)
/execute-plan (메인 = 오케스트레이터, 직접 구현 안 함)
   │
   │  태스크마다: (착수 전 .dev-kit-pause 확인 — 있으면 태스크 경계에서 안전 정지)
   ├─→ tier 라우팅: standard → builder(sonnet) / light → builder-light(haiku)
   │     (신선한 컨텍스트 + role 페르소나 주입, light BLOCKED 시 builder로 1회 승급)
   ├─→ reviewer (sonnet 1차, 읽기 전용, 독립 컨텍스트) — 요구사항 추적표 + PASS/FAIL 판정
   │     (FAIL 시 opus 승격 재검증 — opus verdict가 최종, 오판율 기록.
   │      risk: high 태스크는 FAIL 여부와 무관하게 처음부터 opus)
   ├─→ PLAN.md 체크 + PROGRESS.md 기록 + git 커밋
   └─→ NEXT TASK로 다음 태스크 (반복)
   │
   │  stage 완료 시:
   └─→ stage-reviewer (기본 opus·위험 stage는 fable 승격, 읽기 전용) — 태스크 간 일관성·통합 동작·
        stage 완료 조건 판정. FAIL 시 보완 태스크 추가 후 1회 재검증
   ↓
완료/중단 보고
```

**왜 3역할 분리인가**: 같은 컨텍스트가 자기 작업을 자기가 검증하면 검증이
형식화된다. builder(구현)·reviewer(검증)·오케스트레이터(상태 관리)가 전부
다른 컨텍스트에서 돌아 (1) 검증 독립성, (2) 긴 작업에서 메인 컨텍스트 오염
방지, (3) 태스크 단위 롤백 가능성을 확보한다.

---

## 구성 요소

| 파일 | 역할 |
|---|---|
| `commands/write-plan.md` | 설계 → PLAN.md 분해. 코드를 실제로 읽고 계획, 태스크마다 파일 경로·verify·role·tier·risk 필수, standard 태스크 verify는 신규/확장 테스트 명시 필수, 아키텍처 결정은 DECISIONS로 분리 |
| `commands/execute-plan.md` | 실행 루프 오케스트레이션. 브리핑 작성, tier 라우팅, 병렬 디스패치(**워크트리 격리** — `worktree:` 선언 시에만, off면 순차 강등), 디스패치 전 `.dev-kit-scope` 생산(훅의 스코프 밖 쓰기 차단 입력), 리뷰 루프(호출 직전 CHANGED 한정 `git add -N`으로 신규 파일 스코프 확보), 그룹 머지 + **머지 후 통합 검증 게이트(B-5)**, stage 경계 통합 검증, **RESUME 블록** 갱신(stage 완료·중단 시), 일시정지, 기록(리뷰 명령 목록·`by=orchestrator` 포함) |
| `agents/builder.md` | 태스크 1개를 신선한 컨텍스트에서 구현 (sonnet). tier=standard 코드 태스크는 TDD(red 확인→green) 절차 강제, 범위 밖 수정 금지, verify 통과 후에만 완료 선언, 막히면 BLOCKED 보고 |
| `agents/builder-light.md` | tier=light 태스크(보일러플레이트·설정·픽스처·단순 CRUD) 전담 경량 빌더 (haiku). 판단이 필요하면 즉시 BLOCKED — 추측하지 않는 것이 성능. verify 2회 실패 시 조기 포기, 상위 티어(builder)로 승급 |
| `agents/reviewer.md` | 읽기 전용 검증자 (sonnet 1차, FAIL 시 opus 승격 재검증 · `risk: high`는 처음부터 opus — 아래 모델 티어링 참조). diff 스코프 한정, **요구사항 추적표**(요구사항 전 행 + 실측 증거, 빈칸이면 BLOCKING) + PASS/FAIL + BLOCKING/NON-BLOCKING 구분, TDD 준수(red→green 기록·신규 테스트) 검사, PASS 시 다음 태스크 브리핑(NEXT TASK — role/tier/risk/[P그룹] 포함) 생성. 읽기 전용은 Bash 경유 수정까지 금지 — **VERIFIED에 실행한 Bash 명령을 전량 원문으로 남긴다**(스코프 준수·읽기 전용 준수를 사후 관측 가능하게) |
| `agents/stage-reviewer.md` | stage 통합 검증자 (기본 opus, 위험 stage는 fable 승격 — 아래 모델 티어링 참조. 읽기 전용 — Bash 경유 수정도 금지). 개별 diff 재리뷰 없이 태스크 간 일관성·통합 동작·stage 완료 조건·설계 drift·누적 NON-BLOCKING을 판정, FAIL 시 보완 태스크(PROPOSED TASKS) 제안. VERIFIED에 실행 명령 전량 기록. **오케스트레이터 직접 처리 태스크가 있는 stage는 생략 조건이 전부 무효** — 그 diff의 유일한 독립 검증층 |
| `skills/brainstorming/` | 아이디어 → 설계 확정. 한 번에 하나씩(객관식 우선) 질문으로 목적·제약·성공 기준·비범위를 좁히고, 2~3개 접근법 제시 후 섹션별 확인을 거쳐 DESIGN.md 작성 → write-plan으로 핸드오프 |
| `skills/grill/` | 기존 설계/계획 심문. 숨은 가정·의존 사슬·실패 모드·verify 실효성을 추천 답과 함께 압박 검증, 결과를 문서에 반영. 대형/고위험 작업 전용 |
| `skills/docs/` | 개발자용 기술 문서 4종(ARCHITECTURE.md·API 명세·데이터 모델·ADR) 작성/갱신/drift 검사. 1차 독자는 에이전트 — 좋은 문서가 builder의 코드 탐색 토큰을 대체한다. DECISIONS 결정은 ADR로 자동 기록 |
| `skills/debugging/` | 버그·테스트 실패·예상 밖 동작 시 근본 원인 조사 강제 [엄격]. 재현→격리→역추적→수정+다층 방어 4단계, 종료 조건(재현 테스트 green + 원인 한 문장 설명). 헌법 §5 Iron Law의 실행 절차 |
| `hooks/block-destructive.sh` + `hooks/hooks.json` | **PreToolUse 훅** (matcher: Bash\|Edit\|Write). ① 데이터 파괴 명령(DROP/TRUNCATE/`delete ... where 1=1`/dropdb/pg_restore/`docker compose down -v`/`docker volume rm`/`rm -rf`/`git reset --hard`/`git push --force`(`-f`·`--force-with-lease` 포함)) 차단. ② **되돌리기 범주 전면 차단** — `git checkout <경로>`(브랜치 전환·`-b`는 허용)/`git restore`/`git clean`/`git stash`(list·show 제외)/`git rm`/`git branch -D`(`-d`는 허용)/`git reflog expire`. ③ **스코프 밖 쓰기 차단** — Edit/Write의 file_path가 `.dev-kit-scope` 목록에 없으면 deny(파일 없으면 검사 생략). 프로젝트 루트 `.dev-kit-allow-destructive`로 패턴별 예외(git 추적 필수·stderr에 흔적). 파서 없음·깨진 입력이면 통과(fail open) |
| `hooks/precompact-resume.sh` | **PreCompact 훅**. 컨텍스트 자동 압축 직전 PROGRESS.md 최상단의 RESUME 블록을 기계적으로 갱신(다음 태스크·미결 DECISIONS·base sha·워크트리·마지막 커밋) — 압축으로 컨텍스트를 잃기 전 디스크로 flush하는 안전망. PLAN.md+PROGRESS.md 있는 프로젝트에서만 동작, 실패 시 무조건 exit 0 |
| `skills/harden/` | 환경 하드닝 [엄격]. L1 DB 권한(앱 계정 DDL 제거·마이그레이션 계정 분리) → L4 백업(스케줄·오프사이트·복원 훈련·실패 알림) → L5 격리(dev/prod 이름 분리·복원 스크립트 안전화). **각 항목은 증거 칸을 채워야 완료**, 결과는 HARDENING.md |
| `skills/audit/` | dev-kit 리포 자체 정합성 감사 [엄격, 읽기 전용]. 인벤토리→참조 정합성→계약 일치→규칙 충돌→에이전트 권한→스킬 연동→README 정확성 검사. version 범프 전 필수 관문 |
| `CLAUDE.md.template` | **개발 헌법** (플러그인 외부 배치 필수 — 아래 설치 참조). 자동 라우팅, Karpathy 원칙, 산출물 제약 원칙, 책임 규정, 안전 가드레일 |

---

## 설치

Claude Code 플러그인은 **2단계**다 — 마켓플레이스 등록(카탈로그 추가) 후
플러그인 설치. 이 리포는 자기 자신을 마켓플레이스로 등록하는
`.claude-plugin/marketplace.json`을 포함한다.

### 1. 리포 클론 (헌법 파일을 꺼내오기 위해 필요)

```bash
git clone https://github.com/<username>/dev-kit.git ~/dev/dev-kit
```

이미 클론돼 있으면 `cd ~/dev/dev-kit && git pull`로 최신화.

### 2. 헌법 배치 (필수)

```bash
ln -s ~/dev/dev-kit/CLAUDE.md.template ~/dev/CLAUDE.md   # 모든 프로젝트의 공통 상위 폴더
```

심볼릭 링크이므로 이후 `git pull`만으로 헌법 변경이 즉시 반영된다.
(기존에 `cp`로 배치했다면 `rm ~/dev/CLAUDE.md` 후 위 명령으로 교체.)

**이 파일이 없으면**: 커맨드(`/dev-kit:write-plan` 등)는 작동하지만
자동 라우팅이 없어서 매번 수동으로 커맨드를 쳐야 하고, Karpathy 원칙·
가드레일도 적용되지 않는다. 플러그인은 "도구", CLAUDE.md는 "상시 규칙"이며
Claude Code 구조상 상시 규칙은 CLAUDE.md로만 주입된다.
헌법은 플러그인에 포함할 수 없어(상시 규칙 vs 온디맨드 로드) 기기마다 수동 배치가 필요하다.

### 3. 마켓플레이스 등록 + 플러그인 설치 (Claude Code 안에서)

```
/plugin marketplace add <username>/dev-kit
/plugin install dev-kit@dev-kit
```

설치 후 **Claude Code를 재시작**해야 에이전트/커맨드가 로드된다.
설치 시 스코프는 **user scope**(모든 프로젝트에서 사용)를 선택한다 —
project/local scope는 이 리포에서만 활성화되므로 전역 방법론 용도에 안 맞다.

> ⚠️ **스키마 에러가 나면**: `/plugin install` 시
> `Invalid schema: .../anthropics-claude-plugins-official/... plugins.N.source: Invalid input`
> 같은 에러가 뜰 수 있다. 이건 dev-kit이 아니라 **Anthropic 공식 마켓플레이스**의
> 새 source 타입(`git-subdir`)을 구버전 Claude Code가 인식 못 해서 나는
> 알려진 버그다. 해결: 먼저 `claude update`로 최신 버전으로 올린다.
> 그래도 안 되면 `/plugin marketplace remove anthropics-claude-plugins-official`
> 후 설치하고, 나중에 다시 add한다 (dev-kit 사용에는 지장 없음).

### 4. 확인

```
/plugin           → Installed 탭에 dev-kit enabled
/agents           → dev-kit:builder, dev-kit:builder-light,
                    dev-kit:reviewer, dev-kit:stage-reviewer 표시
```

### 새 기기 추가 요약

기기마다: **① 클론 + 헌법 복사(1·2단계) → ② 마켓플레이스 등록 + 설치(3단계)**.
헌법(CLAUDE.md)은 상위 폴더에 하나만 두면 하위 모든 프로젝트가 자동 상속하므로,
프로젝트마다 복사할 필요는 없다. 세션은 항상 프로젝트 폴더 안에서 켠다.

---

## 사용법

### 기본 — 그냥 요청하면 됨

```
> 보고서 앱에 PDF 내보내기 기능 추가해줘
```

자동 라우팅이 요청을 분류한다:

| 분류 | 조건 | 동작 |
|---|---|---|
| 설계 필요 | 설계 문서 없음, 아이디어 수준 | brainstorming: 질문 → DESIGN.md → 계획으로 |
| 심문 필요 | 대형/고위험 (마이그레이션, 결제·인증 등) | grill: 설계/계획 압박 검증 후 진행 |
| 계획 필요 | 여러 파일, 새 모듈, 설계 판단 | PLAN.md 생성 → 전체 출력 → 즉시 실행 |
| 진행 계속 | PLAN.md에 미완료 태스크 + "진행해" 류 | 미완료 지점부터 자동 재개 |
| 문서 요청 | 아키텍처 문서, API 명세, ERD, ADR, "문서 검사" | docs 스킬: drift 스캔 → 갱신/작성 |
| 버그/오동작 | 버그 수정, 테스트 실패, 예상 밖 동작 | debugging 스킬: 재현→격리→역추적→수정 (조사 없이 수정 없음) |
| 환경 안전 | DB·볼륨·배포 도입, "안전 점검해줘" | harden 스킬: L1 권한 → L4 백업 → L5 격리, 증거 필수 |
| 사소한 작업 | 한 파일, 자명한 수정 | 계획 없이 처리 + 리뷰만 |

애매하면 계획 생성 쪽으로 분류된다 (계획 과잉이 무계획보다 싸다).

### 실행이 멈추는 경우 (사용자 개입 지점)

1. **DECISIONS** — 계획에 아키텍처 결정이 필요하면 실행 전에 물어보고 대기
2. **3회 연속 FAIL** — 같은 태스크가 리뷰를 3번 통과 못 하면 중단·보고
3. **BLOCKED** — builder가 전제 붕괴를 발견하면 (파일 없음, 스펙 모순 등)
4. **파괴적 작업·요구사항 불명** — rm -rf, DROP TABLE, force-push, 프로덕션
   배포 등은 항상 확인. 다음 태스크의 요구사항이 불명확할 때도 멈춘다
5. **stage-reviewer 2회 연속 FAIL** — stage 통합 검증이 보완 후 재검증에도 실패하면 중단·보고
6. **일시정지** — `.dev-kit-pause` 파일 존재 시 태스크 경계에서 안전 정지 (아래 참조)
7. **워크트리 그룹 머지 충돌 / 통합검증 2회 연속 실패** — 충돌은 [P] 그룹
   편성 오류 신호라 즉시 중단·보고, 머지 후 통합검증은 보완 태스크로 1회
   재시도 후에도 실패하면 중단
8. **사용자 중단 지시**

### 실행 중 개입

계획이 출력된 뒤 실행 중에도 수정 지시가 가능하다:

```
> 1.3은 빼고 진행해
> Stage 2는 방식을 바꿔서 ...
```

PLAN.md를 갱신하고 이어간다. 승인 게이트 없이도 계획 교정이 가능한 구조.

### 일시정지 (`.dev-kit-pause`)

루프가 도는 동안 다른 터미널에서:

```bash
touch .dev-kit-pause   # 태스크 경계에서 안전 정지 (커밋 직후 상태)
rm .dev-kit-pause      # 해제 — 이후 "진행해"로 재개
```

진행 중인 태스크는 끝까지 완료·커밋된 후 멈추므로 작업 트리가 항상 깨끗하다.
즉시 정지가 필요하면 Esc — 단, 미완성 파일이 남을 수 있으니 `git status`
확인을 권장한다.

### 수동 커맨드 (자동 라우팅 오버라이드)

```
/dev-kit:write-plan [설명]     # 계획만 만들고 실행 안 함
/dev-kit:execute-plan          # 실행만 (첫 미완료 태스크부터)
/dev-kit:execute-plan stage 2  # 특정 stage만
```

---

## PLAN.md 형식

`/write-plan`이 생성한다. 직접 써도 무방하다.

**태스크의 단위는 시간이 아니라 verify다** — "verify 하나로 통과/실패가 갈리는
단위 = 신규/확장 테스트 1~2개 + 그 구현"(대략 5~10분). 이 범위를 넘으면 쪼갠다.
에이전트는 소요 시간을 추정하지 못하지만 "verify 하나"는 산출물로 확인 가능하다 —
강제되는 기준은 관측 가능한 기준이어야 한다(헌법 §1 산출물 제약).

```markdown
# PLAN: PDF 내보내기
작성: 2026-07-12 · 상태: IN PROGRESS

## DECISIONS (사용자 결정 필요 — 비어있으면 생략)
- [ ] D1: PDF 라이브러리 — puppeteer(정확한 렌더링, 무거움) vs pdfkit(가벼움, 레이아웃 수동)

## Stage 1: 데이터 준비 — 완료 조건: export API가 JSON 반환
- [ ] 1.1 export 서비스 + 직렬화 유닛테스트 2개 · 파일: `services/export.ts` (신규) · role: backend · tier: standard · risk: high · verify: 신규 테스트 2개 red→green
- [ ] 1.2 [P1] 템플릿 컴포넌트 + 렌더 테스트 · 파일: `components/PdfTemplate.tsx` (신규) · role: frontend · tier: standard · risk: normal · verify: 신규 렌더 테스트 red→green + 스토리북 확인
- [ ] 1.3 [P1] 테스트 픽스처 · 파일: `tests/fixtures/report.ts` (신규) · role: test · tier: light · risk: normal · verify: import 에러 없음
```

- **role 태그**: 실행 시 builder에게 해당 전문가 페르소나가 주입된다
  (frontend/backend/db/test/infra/docs/general). 별도 에이전트 파일 불필요 —
  오케스트레이터가 태스크에 맞는 역할 지침을 브리핑에 즉석 작성한다.
- **tier 태그**: `light`(보일러플레이트·설정·픽스처·단순 CRUD — 판단 불필요)는
  builder-light(haiku), `standard`(그 외 전부)는 builder(sonnet)로 라우팅된다.
  판단이 조금이라도 들어가면 standard, 애매해도 standard — 잘못된 light는
  재시도 비용으로 절감분을 까먹는다. light가 BLOCKED되면 builder로 1회 승급.
- **risk 태그**: `high`(요구사항에 수치·경계·개수 조건, 보안, 데이터 변형/삭제,
  동시성 포함) 또는 `normal`(기본). high는 FAIL 여부와 무관하게 **처음부터
  opus 리뷰어**로 라우팅된다 — 약한 리뷰어가 놓쳐서 PASS시킨 결함은 사후
  승격(FAIL 시 승격)으로는 잡히지 않기 때문이다. 태그 생략 시 normal.
- **[P그룹]**: 같은 번호끼리 병렬 실행 — 단 프로젝트에 `worktree:` 선언
  (shared-env|isolated-env)이 있을 때만 실제로 병렬(워크트리 격리)이고,
  없으면/off면 순차 강등된다. 조건: 상호 의존 없음 + 파일 안 겹침 +
  **네임스페이스 안 겹침**(마이그레이션 버전·라우트·설정 키·픽스처 이름·DI
  등록명) + 의존성 변경 태스크 아님. 동시 최대 3개 (토큰 소모가 병렬 수에
  비례). 리뷰는 각 워크트리 안에서 태스크별 수행, 그룹 내 리뷰에서는
  NEXT TASK 생략(마지막 리뷰만 포함). 그룹 머지 후 통합 검증 게이트 통과
  시에만 다음으로 (위 "워크트리 격리" 참조).

---

## 기록 체계 (감사 추적)

| 파일 | 내용 | 용도 |
|---|---|---|
| `PLAN.md` | 뭘 할지 + 체크 상태 | 진행률 파악, 세션 재개 기준점 |
| `PROGRESS.md` | 태스크별 실행 일지 — 구조화 헤더(결과·시도 횟수·모델 또는 `by=orchestrator`·tier·risk) + 리뷰어가 실행한 Bash 명령 목록(원문) + 변경 내용, 검증 결과, FAIL 사유(유형 태그), 넘긴 사항. stage 통합검증 결과도 동일 형식. **롤링 요약**: stage 종료 시 해당 stage 블록을 요약 한 줄로 압축 — 최근 5개 태스크만 전문 유지, 파일 크기(=stage-reviewer 입력)가 상수로 유지된다 | 자리 비웠다 와서 훑기, 문제 역추적, 검증 통계 집계 |
| `PROGRESS.archive.md` | 압축된 stage 블록의 원문 보관소 (stage 종료 시 자동 append) | 추적 가능성 유지, 검증 통계의 과거분 집계. 루프의 어떤 에이전트도 읽지 않는다 |
| git 커밋 | 태스크당 1커밋 `[plan 1.2] 목표` | 태스크 단위 diff·bisect·롤백 |
| `ARCHITECTURE.md` + `docs/` | 시스템 현재 상태 (구조·계약·데이터 모델), `docs/decisions/`는 ADR(불변) | builder의 탐색 대체 컨텍스트, 결정 맥락 보존 (docs 스킬 관리) |
| raw 트랜스크립트 | `~/.claude/projects/` (Claude Code 자동) | 브리핑/verdict 원문 디버깅용 |

### 검증 로그 계측 — 검증이 실제로 작동하는지 측정

PROGRESS.md의 구조화 라인은 grep 가능한 계측 데이터다. 루프 완료/중단
보고에 검증 통계(총 태스크·1회 통과·재시도율·BLOCKED·tier 분포·FAIL 유형)가
자동 포함되며, 직접 세려면:

```bash
grep -h "^## .* Task" PROGRESS.md PROGRESS.archive.md | grep -c "시도 [2-9]회"   # 재시도 발생 태스크 수 (압축된 과거분은 archive에)
grep -c "by=orchestrator" PROGRESS.md PROGRESS.archive.md                        # 독립 검증을 안 거친 태스크 수 (stage-reviewer 생략 판정 근거)
grep -A1 "^- 리뷰명령:" PROGRESS.md | grep -c "git diff --"                       # 리뷰어가 스코프를 실제로 한정했는지
```

v1.7부터 리뷰어가 실행한 Bash 명령이 PROGRESS.md에 원문으로 남는다. 이전에는
로그 전체에서 `git diff`/`git status` 언급이 5건뿐이라 **리뷰어가 무엇으로
diff를 봤는지 사후 판별이 불가능했다** — 결함이 있었더라도 관측이 안 되는
상태였다. 이 목록으로 스코프 준수와 읽기 전용 준수가 동시에 관측된다.

해석 기준 — **재시도율 10~30%가 건강 범위**:
- **0%에 수렴** → 리뷰어가 형식적으로 통과시키는 중일 가능성. reviewer의
  BLOCKING 기준(확신 8/10)을 강화하라.
- **30% 초과** → builder 티어가 낮거나 태스크 정의가 모호하다는 신호.
  tier 배분(light 남용 여부)과 PLAN.md 태스크의 verify 구체성을 재검토하라.

리뷰 2단 티어링 도입 후 추가 감시 (사전 승격이 `risk: high` 태스크의
false-PASS를 덮지만, normal 태스크의 false-PASS는 여전히 이 지표로만 잡는다):
- **재시도율이 기존 대비 급락** (예: 5% → 0~2%) → sonnet 리뷰가 느슨하다는
  신호. reviewer 기본 모델을 opus로 되돌려라 (frontmatter 한 줄).
- **stage-reviewer(opus 유지) FINDINGS 증가** → 태스크 리뷰가 놓친 결함이
  stage에서 잡히고 있다는 뜻 — 같은 롤백 대상.
- **오판율**(승격 중 PASS로 뒤집힘)이 높으면 sonnet이 과하게 깐깐한 것 —
  이건 품질 문제가 아니라 승격 비용 문제이므로 관찰만 해도 된다.

---

## 규율 체계

### 규율은 산출물로 강제한다 (헌법 §1)
리뷰어 감도 실험(같은 모델, 지시문만 교체, 4라운드) 결과: **"무엇을 확인하라"는
서술형 지침은 반복적으로 무시됐고, "출력의 이 칸을 이런 증거로 채워라, 못 채우면
실패"라는 산출물 제약은 지켜졌다** (결함 검출 2/4 → 4/4).
따라서 반드시 지켜져야 하는 검사는 지시문이 아니라 **출력 필드**로 표현한다.
새 규율을 넣을 때의 자문: 안 지켰을 때 산출물에 빈칸으로 드러나는가?
드러나지 않으면 그 규율은 강제되지 않는다.

이 원칙의 첫 적용이 reviewer의 **요구사항 추적표**다 (v1.6):
- reviewer는 VERIFIED 앞에 브리핑의 요구사항을 **한 줄도 빠짐없이** 행으로
  나열하고 각 행에 충족 증거를 적는다.
- 수치·경계·길이·개수 조건은 **코드를 읽은 것이 증거가 될 수 없다** —
  `python -c` 등으로 실제 값을 계산하고 명령과 출력을 그대로 붙인다.
  부재 판정(미구현)은 grep/diff 결과를 증거로 쓴다.
- `builder VERIFY에 red→green 기록이 있는가`는 전용 행으로 검사한다.
- 증거를 못 채운 행이 하나라도 있으면 그 자체로 BLOCKING이고,
  BLOCKING을 찾아도 표는 끝까지 완성한다(첫 BLOCKING에서 중단 금지).

### 파괴 방어 3층 (v1.8)
파괴 사고를 막는 층은 셋이고 **아래로 갈수록 강하다**:

| 층 | 수단 | 뚫리는 지점 |
|---|---|---|
| 1. 지시문 | 헌법 §5 가드레일 + builder DESTRUCTIVE 행 | 모델이 무시하면 끝 (그래서 산출물 칸으로 관측만 확보) |
| 2. 훅 | `hooks/block-destructive.sh` (PreToolUse deny) | **문자열 매칭이라 `.sql` 파일 경유·변수 조립으로 우회 가능** |
| 3. 환경 | harden 스킬 L1 (DB 권한) | 권한이 없으면 실행 자체가 불가능 — 최종 보증 |

훅은 심층방어의 한 겹일 뿐 보증이 아니다. **DB가 있는 프로젝트는 harden L1을
먼저 한다** (write-plan이 HARDENING.md 없으면 Stage 1에 태스크를 심는다).

훅의 알려진 한계와 설계 선택:
- `psql -f reset.sql`처럼 파일 경유하면 매칭되지 않는다
- `CMD="drop table x"; psql -c "$CMD"`처럼 변수 조립하면 매칭되지 않는다
- 반대로 SQL 키워드가 문자열로 들어간 `git commit -m "drop table 지원"`은
  오탐이라, 파이프·연결(`| ; &`)이 없는 단독 `git commit`/`git log`/`echo`/
  `printf`는 예외 처리했다 (DB에 도달할 수 없는 명령이므로)
- 상시 허용이 필요하면 `.dev-kit-allow-destructive`에 패턴 ID를 적는다.
  이 파일은 **`.gitignore` 금지** — git에 추적돼야 리뷰에서 보인다

**되돌리기 범주 (v1.8.1)** — 세 실사고 중 두 번째(문서 태스크 에이전트가
`git checkout tests/...`로 병렬 태스크의 미커밋 산출물 파괴)의 직접 대응.
이것은 목록 나열이 아니라 **"미커밋 작업을 없애거나 워킹트리를 되돌리는 모든
명령"이라는 범주**다 — 변종이 나오면 범주 기준으로 판단해 스크립트에 추가한다.
`git checkout`/`git restore`/`git clean`/`git stash`/`git rm`/`git branch -D`/
`git reflog expire`가 현재 표면이고, 전부 **확인이 아니라 전면 금지**다
(복구는 사용자 몫). 오탐 방지 설계 — 워크트리 격리가 브랜치 조작에 의존하므로
이 구분이 정확해야 한다:
- `git checkout -b`(생성)·`git checkout <브랜치>`(전환)는 허용 — **경로 인자가
  있는 형태만** 차단한다. 판별은 인자의 파일 실존 검사(cwd 기준)로 한다.
  알려진 한계: 워킹트리에서 이미 삭제된 파일의 checkout은 `--` 없이 쓰면
  실존 검사를 통과한다.
- `git branch -d`(머지 확인 삭제)·`git stash list/show`·`git worktree
  add/remove/prune`은 허용 (실측 49케이스로 차단·오탐 양방향 검증).

**스코프 밖 쓰기 차단 (v1.8.1)** — 세 번째 실사고(reviewer의 읽기 전용 위반)
대응의 기계층. 오케스트레이터가 디스패치 직전 `.dev-kit-scope`에 대상 파일
목록을 쓰면, 훅이 목록 밖 Edit/Write를 deny한다(파일 없으면 검사 생략 —
수동 세션 대응). **한계: 동시 디스패치된 태스크 간 교차는 이 방식으로 못
막는다** — 둘 다 목록에 있기 때문이다. 그 층은 워크트리 격리(아래)가 담당한다.

**역할 분담 — 훅이 막고, DESTRUCTIVE 행이 계측한다.** 산출물 강제(builder의
DESTRUCTIVE 행)만으로는 사고를 막지 못한다 — 드러나는 시점이 이미 파괴 후다.
차단은 훅(1.5층), 관측·감사는 DESTRUCTIVE 행(1층), 최종 보증은 권한(3층)이다.

### 워크트리 격리 (v1.8.1)

[P] 병렬 그룹을 태스크마다 전용 git worktree에서 실행해 **물리적으로**
격리한다 — 마크다운 규칙이 세 번 못 막은 것을 파일시스템이 막는다.
병렬 태스크가 서로의 미커밋 산출물을 건드릴 방법 자체가 없어진다.

프로젝트 CLAUDE.md에 선언해야 켜진다 (없으면 `off`):

```
worktree: shared-env | isolated-env | off
worktree-env-setup: <각 워크트리에서 실행할 준비 명령>
```

- `shared-env` — 메인 트리의 의존성 환경 재사용
  (예: uv면 `export UV_PROJECT_ENVIRONMENT=<메인트리>/.venv`)
- `isolated-env` — 워크트리마다 설치 (`worktree-env-setup`에 설치 명령)
- `off`(기본) — [P] 그룹을 **순차 실행으로 강등**. off가 기본인 이유:
  환경 공유 가능 여부는 스택마다 다르고, 잘못 켜면 의존성 없는 워크트리에서
  verify가 거짓 실패한다.

핵심 규칙 (상세: `commands/execute-plan.md`):
- 위치는 반드시 `<dev 루트>/.worktrees/<project>/<task-id>` — dev 루트 아래여야
  공통 헌법이 상속된다. `/tmp`에 만들면 에이전트가 규칙 없이 돈다.
  브랜치는 `wt/<task-id>`, 수명은 [P] 그룹 단위(끝나면 머지 후 즉시 제거 —
  살아 있을수록 충돌이 커진다). `.worktrees/`는 dev 루트 `.gitignore`에.
- PLAN.md·PROGRESS.md는 메인 트리 소유 — 워크트리 태스크는 읽지도 쓰지도
  않는다 (건드리면 머지마다 충돌한다). reviewer는 워크트리 안에서
  `git diff HEAD~1`로 리뷰 — 남의 변경이 물리적으로 없어 스코프 자동 보장.
- **머지 후 통합 검증 게이트**: 워크트리 격리의 구조적 대가는 verify가 격리
  상태에서만 도는 것이다 — A도 통과, B도 통과했는데 **머지된 결과는 아무도
  검증하지 않은 상태**가 된다. 그래서 그룹 머지 직후 모든 태스크의 verify를
  메인 트리에서 재실행한다(오케스트레이터 직접 실행, 모델 호출 없음 — 비용은
  테스트 시간뿐. 그룹 크기 1이면 생략). 실패 시 워크트리 보존 + 보완 태스크,
  2회 연속 실패 시 중단·보고.
- write-plan의 [P] 편성 조건도 강화됐다: 파일 비중첩만으로는 부족하고,
  **같은 네임스페이스**(마이그레이션 버전 번호, 라우트 경로, 설정 키, 픽스처
  이름, DI 등록명)를 공유하면 [P] 금지. 의존성 변경 태스크도 [P] 금지
  (shared-env 동시 설치 경합).
- 정리 실패는 루프를 멈추지 않는다 — 경고 후 진행, 다음 실행 시작 시
  `git worktree prune`이 회수. BLOCKED·통합 실패 태스크의 워크트리는
  보존하고 경로를 보고에 포함한다.

### 세션 체크포인트 (v1.8.1)

- **RESUME 블록**: stage 완료 시·루프 중단 시 오케스트레이터가 PROGRESS.md
  최상단에 갱신한다 — 다음 태스크, 미결 DECISIONS, 누적 NON-BLOCKING,
  stage base sha·남은 워크트리, 마지막 커밋 sha. 새 세션은 PROGRESS 전체를
  훑지 않고 이 블록만 읽고 재개한다.
- **PreCompact 훅**: 컨텍스트 자동 압축 직전 같은 블록을 기계적으로 갱신한다
  (셸에서 수집 가능한 필드만) — 압축으로 컨텍스트를 잃기 전 디스크로 flush하는
  안전망. PreCompact는 컨텍스트 주입이 불가능하고 부수 효과만 가능하므로
  (공식 문서 확인) 디스크 flush가 유일한 안전망 형태다.
- **dev-kit에서는 `/compact`보다 `/clear`가 낫다.** 진행 상태가 전부 파일
  (PLAN.md·PROGRESS.md·커밋)에 있으므로, 압축 요약은 이미 디스크에 있는
  정보를 토큰을 써서 다시 만드는 것이다. 긴 세션은 비용뿐 아니라 규칙 준수도
  저하시킨다(CLAUDE.md 규칙의 우선순위가 대화 길이에 밀린다). stage 완료
  시점에 컨텍스트 사용률이 높으면 오케스트레이터가 "`/clear` 후 '진행해'로
  재개"를 권고한다.

### 신규 파일 스코프 (v1.7)
`git diff`는 **untracked 신규 파일을 보여주지 않는다**(실측 재현 확인). PLAN.md
태스크의 상당수가 `(신규)` 파일이고 TDD 신규 테스트도 대부분 신규 파일이라,
리뷰어가 지시대로 `git diff`만 보면 신규 테스트를 못 보고 "테스트 없음"으로
오판하거나 요구사항 추적표의 부재 판정 증거가 거짓이 된다.

→ 오케스트레이터가 reviewer 호출 **직전에** builder의 CHANGED 목록으로 한정해
`git add -N <파일들>`(intent-to-add)을 실행한다. 실측 확인 사항:
- intent-to-add 파일은 `git diff`에 전문이 노출된다
- 다른 파일만 부분 스테이징해 커밋해도 **딸려 들어가지 않는다**(워킹트리에 `A`로 남음)
- `git add -N .`은 병렬 그룹에서 남의 태스크 파일까지 등록하므로 **금지**
- `git commit -a`는 딸려 보내므로 금지 — 커밋은 CHANGED 한정 `git add`로만
- 이 명령은 오케스트레이터 전용 — reviewer가 직접 실행하면 읽기 전용 위반이다

### 리뷰어 읽기 전용의 실질 (v1.6~v1.7)
reviewer/stage-reviewer는 Write/Edit 도구가 없다 — 하지만 도구가 없다고
읽기 전용이 성립하는 게 아니다. **Bash 경유 수정(sed -i, 리다이렉션, 스크립트
실행)도 금지**한다. 뮤테이션 검증이 필요하면 파일을 고치지 말고 `python -c`로
함수를 직접 호출해 값을 확인하거나 리포 사본·git stash 위에서 한다
(실측상 python -c만으로 동일한 검증이 가능했다).

v1.7에서 이 규율에 **관측 수단**을 붙였다: 리뷰어는 VERIFIED에 실행한 Bash
명령을 전량 원문으로 나열하고, 오케스트레이터가 그 목록을 PROGRESS.md에 그대로
옮긴다. 파일을 수정하는 명령이 목록에 있으면 리뷰 결과와 무관하게 규칙 위반으로
보고된다. 규율(v1.6)만 있고 산출물 칸(v1.7)이 없던 동안은 준수 여부를 확인할
방법이 없었다 — 헌법 §1이 말하는 "빈칸으로 드러나지 않으면 강제되지 않는다"의
자기 사례다.

### [엄격] / [유연] 분류
모든 스킬 상단과 헌법 주요 섹션에 규율 강도를 표기한다:
- **[엄격]** — 정확히 따른다. 맥락·급함을 이유로 완화하지 않는다:
  TDD(§3), debugging 4단계, 검증 루프(§4), 안전 가드레일(§5), audit.
- **[유연]** — 원칙을 유지하되 적용 방식은 맥락에 맞게 적응한다:
  brainstorming 질문 방식, docs 문서 형식, 세리머니 규모(§3).

스킬 내부 세분을 허용한다 — 예: brainstorming 전체는 [유연]이되
"최소 안전선"(목적·성공 기준·비범위)은 [엄격].

### TDD (tier=standard 코드 태스크 한정)
실패하는 테스트 먼저 작성 → 실패 실제 확인(red) → 통과시키는 최소 코드(green).
- builder는 VERIFY에 **red→green 두 실행 결과**를 기록해야 하고, 처음부터
  통과하는 테스트는 다시 쓴다 (기존 동작만 검증하고 있다는 신호).
- reviewer는 red→green 기록을 **요구사항 추적표의 전용 행**으로 감사하고,
  신규 테스트 부재를 BLOCKING(`verify 미충족`)으로 판정하며,
  assert 없는 가짜 테스트도 잡는다.
- write-plan은 standard 태스크의 verify에 신규/확장 테스트 명시를 요구하고,
  테스트 인프라가 없으면 Stage 1에 셋업 태스크를 넣는다.
- 예외: tier=light, role=docs, 테스트 인프라 최초 셋업 태스크.

## 모델 티어링

판단 밀도에 맞춰 역할별로 모델을 배치한다:

| 역할 | 모델 | 근거 |
|---|---|---|
| 설계 (brainstorming / grill / write-plan — 메인 세션) | fable 권장 | 계획 품질이 루프 전체를 결정 — 여기 아끼면 뒤에서 다 낸다 |
| 실행 루프 오케스트레이션 (메인 세션) | `/model opus`로 낮추기 권장 | 상태 관리·브리핑 작성 위주, 최고 티어 불필요 |
| stage-reviewer | 기본 opus, 조건부 fable 승격 | 통합 판정은 보통 opus로 충분. 승격 조건: 인증·결제·데이터 마이그레이션·외부 연동·되돌리기 어려운 변경 포함 stage, 또는 DECISIONS 항목이 구현된 stage. 승격 사유는 PROGRESS.md에 기록 |
| reviewer | sonnet 1차, FAIL 시 opus 재검증(사후 승격) · `risk: high` 태스크는 처음부터 opus(사전 승격) | 호출의 대다수(실측 95%)가 PASS 확인 — 여기에 opus는 과잉. FAIL일 때만 opus가 재검증해 verdict를 확정한다(오버헤드는 FAIL율만큼만). 사후 승격은 라운드마다 독립 — 수정 후 재검증은 다시 sonnet 기본 호출부터 시작한다(직전 라운드가 opus였어도 opus를 이어 쓰지 않는다). 사후 승격만으로는 sonnet의 false-PASS(결함을 놓치고 통과)를 못 잡으므로 — 놓친 결함은 FAIL을 내지 않아 승격 자체를 트리거하지 못한다 — 실패 비용이 큰 조건(`risk: high`)은 사전 승격으로 처음부터 opus에 보낸다. 사전 승격은 태스크 속성이라 모든 라운드에서 유지된다 |
| builder | sonnet (frontmatter 고정) | 태스크 단위 구현 |
| builder-light | haiku (frontmatter 고정) | 판단 없는 기계적 작업 |

stage-reviewer 조건부 승격의 동작 방식: frontmatter는 `model: claude-fable-5`
(**전체 모델 ID 필수** — `fable` 별칭은 frontmatter에서 무효라 호출 자체가
실패한다, v1.3.3에서 수정)로 두고, execute-plan이 기본 호출 시 Task 파라미터로
`model: opus`를 명시해 강등한다 (파라미터가 frontmatter를 덮어쓰는 동작은 실측
검증됨). 승격 조건이면 파라미터를 생략해 frontmatter가 적용된다 — Task 파라미터는
haiku/sonnet/opus 별칭만 받아 fable을 직접 지정할 수 없으므로 강등 방향으로
설계했다. 실제 투입 모델은 PROGRESS.md의 `model=` 기록으로 확인한다.

> ⚠️ `CLAUDE_CODE_SUBAGENT_MODEL` 환경변수가 설정돼 있으면 에이전트
> frontmatter의 model을 전부 덮어써 티어링이 무력화된다. 설정하지 마라.

## 토큰 관리

이 워크플로우는 태스크마다 서브에이전트를 띄우므로 단일 세션 대비 토큰을
많이 쓴다 (서브에이전트 다용 워크플로우는 수 배 소모 가능). 내장된 완화 장치:

- PROGRESS.md 롤링 요약 — stage 종료 시 압축으로 stage-reviewer 입력 상수화
- 자명한 소형 태스크는 오케스트레이터가 builder 없이 직접 처리
- 연속 소형 태스크 2~3개는 하나의 builder로 묶기 (verify는 개별 실행)
- 병렬 동시 상한 3
- 브리핑은 자족적 최소한으로 — 프로젝트 전체 맥락 주입 금지
- 리뷰어 스코프는 해당 태스크 diff만
- 리뷰 명령 목록(v1.7)은 PROGRESS.md를 키우지만 stage 종료 시 롤링 요약이
  압축한다 — 요약 라인에는 명령 목록을 흡수하지 않고 archive에만 남긴다
- role 페르소나는 write-plan이 PLAN.md `## ROLES`에 1회 생성 — 브리핑은 복사만
- stage 경계 세션 재시작 권고 — 롤링 요약 후 새 세션 재개로 메인 컨텍스트
  리셋 (PLAN/PROGRESS 기반 재개는 무손실)

토큰이 빠듯하면 [P] 그룹을 순차로 돌리라고 지시하면 된다 (속도↔토큰 트레이드오프).

## 튜닝 가이드

- **중단 조건 4(파괴적 작업)나 BLOCKED가 자주 걸림** → PLAN.md 태스크 정의가
  모호하다는 신호. 멈춘 지점의 질문을 보고 완료 조건을 구체화하라.
- **리뷰어가 너무 깐깐해서 루프가 김** → reviewer.md의 "확신 8/10 미만은
  NON-BLOCKING" 기준을 조정하라.
- **리뷰 비용이 예상보다 큼** → PLAN.md의 `risk: high` 비율을 보라. 절반을
  넘으면 태그가 남발된 것이다 (사전 승격 = 처음부터 opus). 판정 기준은
  "요구사항에 수치·경계·개수 조건, 보안, 데이터 변형/삭제, 동시성이 실제로
  있는가"이지 "중요해 보이는가"가 아니다.
- **특정 프로젝트만 계획 승인 후 실행하고 싶음** → 그 프로젝트의 CLAUDE.md에
  "이 프로젝트는 계획 승인 후 실행" 한 줄 추가 (하위가 상위를 덮어씀).
- **에이전트가 만든 계획이 의도와 자주 어긋남** → dev/CLAUDE.md 라우팅 3번에서
  "확인 대기 없이"를 "요약 확인 후"로 바꾸면 승인 게이트 1개가 생긴다.

## 환경별 세팅 & 함정

### OS 지원
dev-kit 자체는 순수 마크다운이라 Windows / Linux / macOS 전부 동일하게
작동한다. 함정은 주변 환경에서 나온다.

### Windows
- **WSL 권장.** 네이티브(Node.js 필요)도 되지만, verify 명령·훅·gstack 등
  셸 의존 요소가 늘어날수록 WSL이 문제가 적다. WSL 사용 시 프로젝트를
  Windows 마운트(`/mnt/c/...`)가 아닌 **WSL 파일시스템 안에** 두어야
  파일 I/O 성능이 정상이다.
- **CRLF 함정**: builder가 만든 파일과 기존 파일의 줄바꿈이 섞이면
  diff가 파일 전체로 잡혀 reviewer 스코프가 오염된다. 리포마다
  `.gitattributes`에 `* text=auto eol=lf` 를 넣어 고정하라.
- gstack(선택)을 쓸 경우: Git Bash/WSL 필요, Bun + Node 둘 다 필요,
  개발자 모드 없으면 `git pull` 후 `./setup` 재실행 필요.

### macOS / Linux
- 특별한 함정 없음. 단 macOS 기본 bash(3.x)와 Linux bash(5.x) 차이로
  verify 스크립트가 갈릴 수 있으니 아래 "verify 이식성"을 따르라.

### verify 이식성 (멀티 OS로 작업할 때 중요)
PLAN.md의 verify에 OS 종속 셸 명령을 직접 쓰지 마라
(`rm -rf`, 파이프 체인, `&&` 연쇄 등). 대신 **패키지 스크립트로 감싸라**:
`npm run test:unit`, `make check` 처럼. 같은 PLAN.md가 어느 기기에서
재개돼도 verify가 동일하게 돈다. `/write-plan`에게
"verify는 npm 스크립트로만 작성"이라고 프로젝트 CLAUDE.md에 못 박아두면 강제된다.

### git — 자동 커밋 관련
- **feature 브랜치에서 돌려라.** 태스크당 1커밋이 main에 직접 쌓이는 것을
  막으려면, 실행 루프는 브랜치에서 돌리고 완료 후 사람이 머지한다.
  프로젝트 CLAUDE.md에 "execute-plan은 `plan/<기능명>` 브랜치 생성 후 실행"
  한 줄이면 강제된다.
- **push는 수동.** 태스크마다 push하면 CI가 태스크 수만큼 돈다.
  커밋은 로컬에 쌓고 push는 stage 완료 또는 전체 완료 시점에.
- **PLAN.md / PROGRESS.md 커밋 여부**: 커밋 권장 (감사 추적이 히스토리에
  남고, 다른 기기에서 이어서 실행 가능). 지저분한 게 싫으면 머지 시
  squash하거나 `.gitignore`에 넣어라 — 단 ignore하면 기기 간 재개가 안 된다.

### 권한 & 시크릿
- `--dangerously-skip-permissions`로 상시 운용하지 마라. 자동 루프일수록
  파괴적 명령 확인(중단 조건 4)이 마지막 방어선이다. 반복 승인이 귀찮으면
  settings.json의 permission rules로 **안전한 명령만** allowlist하라.
- `.env` 등 시크릿 파일은 permission deny rule로 읽기 자체를 차단하라.
  세션 트랜스크립트는 평문 저장이라, 도구가 읽은 시크릿은 로그에 남는다.
- 배포 크리덴셜(클라우드 키, DB 접속 정보)은 루프가 접근할 수 없는 곳에
  두고, 배포 자체는 자동 루프 밖(사람 또는 CI)에서 수행하라.

### 배포 환경
- 자동 루프의 종점은 "리뷰 PASS + 테스트 통과 + 로컬 커밋"까지다.
  **프로덕션 배포는 루프에 넣지 마라** — 헌법 §5가 파괴적 작업으로 분류해
  어차피 멈추지만, 애초에 PLAN.md 태스크로 만들지 않는 게 맞다.
- 스테이징 배포까지 자동화하고 싶으면: push → CI가 스테이징 배포 →
  Playwright/QA는 스테이징 URL 대상으로. 배포 권한을 루프가 아닌 CI에 두는 구조.

### 플랜/토큰 한도
병렬 실행은 사용량을 병렬 수만큼 동시에 소모해 플랜 한도에 빨리 도달한다.
Pro 플랜이면 [P] 그룹 없이 순차 운용을 기본으로, Max 플랜 이상에서 병렬을
켜는 것을 권장한다. 한도 도달로 세션이 끊겨도 PLAN.md/PROGRESS.md 기반으로
"진행해" 한마디에 재개된다 — 이 재개 가능성이 기록 체계의 존재 이유 중 하나다.

**여러 세션 병렬 운용** 시에도 같은 원리로 세션 수만큼 한도가 비례 소모된다.
실행 루프 세션은 `/model opus`로 돌려라 (execute-plan 사전 체크가 fable
감지 시 전환을 권고한다) — 실행 루프는 시간당 토큰 소모가 가장 큰 활동이라
fable 한도를 여기 쓰면 정작 fable이 차이를 만드는 설계 세션
(brainstorming/grill/write-plan)과 위험 stage 승격에 쓸 예산이 사라진다.

### 모델 라우팅 트러블슈팅 (실측 기반)
승격/강등 메커니즘 자체는 위 "모델 티어링" 참조. 아래는 증상별 원인과 해결.

- **서브에이전트 호출이 "There's an issue with the selected model (X)"로 즉시 실패**
  → frontmatter `model:`에 무효 별칭을 쓴 것. `haiku`/`sonnet`/`opus` 별칭만
  해석되며, 최신 프론티어 모델(fable)은 별칭이 없어 **전체 모델 ID**
  (`claude-fable-5`)를 써야 한다 (v1.3.3에서 수정된 버그).
- **별칭이 옛 모델로 풀림** (PROGRESS.md `model=` 기록이 구세대 모델)
  → 별칭→모델 ID 매핑은 **설치된 Claude Code 빌드에 고정**된다. `claude --version`
  확인 후 CLI를 업데이트하라 (실측: 2.1.42는 opus→4.6·sonnet→4.5,
  2.1.220은 opus→5·sonnet→5). dev-kit 에이전트는 별칭 기반이라 CLI만 올리면
  파일 수정 없이 자동 승격된다 — 전체 ID로 고정한 stage-reviewer만
  모델 세대 교체 때 수동 갱신 대상이다.
- **에이전트 frontmatter를 고쳤는데 반영이 안 됨** — 캐시가 두 겹이다:
  (a) 에이전트 정의는 **세션 시작 시 메모리에 로드**되므로 파일을 고쳐도
  현재 세션에는 반영되지 않는다 — 새 세션이 필요하다.
  (b) 플러그인 에이전트는 리포가 아니라 **설치 캐시**
  (`~/.claude/plugins/cache/<마켓플레이스>/<플러그인>/<버전>/`)에서 로드된다 —
  리포 수정만으로는 부족하고 plugin update가 필요하다.
- **라우팅이 의도대로 되는지 검증하는 법**: 해당 서브에이전트를 호출해
  "시스템 프롬프트의 실행 모델 ID('You are powered by ...' 줄)를 보고하라"고
  시키면 실제 투입 모델을 실측할 수 있다. 새 세션 검증이 필요하면
  `claude -p`(헤드리스)로 Task 호출을 시켜서 확인한다.
- **pnpm 글로벌 설치/업데이트 후 "claude native binary not installed"**
  → pnpm v10이 postinstall 스크립트를 기본 차단한다. 해결: 글로벌 매니페스트
  (`~/Library/pnpm/global/5/package.json` 등)에
  `"pnpm": { "onlyBuiltDependencies": ["@anthropic-ai/claude-code"] }`를
  등록하면 이후 업데이트부터 자동이다. 당장 복구는
  `node <글로벌 node_modules>/@anthropic-ai/claude-code/install.cjs` 1회 실행.

---

## 확장 — 도메인 지식 스킬 추가

디자인, 유튜브/블로그 자동화 같은 참고 지식은 `skills/`에 추가한다.
스킬은 평소엔 이름+설명(목차)만 로드되고 관련 작업일 때만 본문이 로드되므로,
지식이 쌓여도 상시 컨텍스트 비용이 늘지 않는다.

```
skills/
├── _template/            # 새 스킬 만들 때 복사 (작성 가이드 포함)
├── design/               # 예: UI/UX 기준 + references/ 상세 문서
├── youtube-automation/   # 예: 쇼츠/롱폼 파이프라인 절차
└── blog-automation/      # 예: 발행 체크리스트, SEO 기준
```

원칙: SKILL.md는 목차+핵심 원칙만(200줄 이하), 상세 본문은 references/로
분리해 필요할 때만 읽히게 한다. 상세 가이드는 `skills/_template/SKILL.md` 참조.
추가 후 `plugin.json` version 올리고 push → 모든 기기에서 `/plugin update dev-kit`.

⚠️ 사업 민감 정보(수익화 전략, 채널 데이터 등)는 public 리포에 넣지 말 것.
필요 시 리포를 private으로 전환 — private이어도 인증된 기기에선 설치 가능.

---

## 로드맵 — 추가 후보 (skills/로 확장)

우선순위 순. 각각 `skills/_template/` 구조로 추가하면 된다.

1. **design** — 하이 취향의 디자인 기준(색·타이포·레이아웃·컴포넌트 관례).
   Anthropic 공식 frontend-design(범용 anti-slop)과 역할 분담: 공식 것은
   "AI 티 안 나게", 이건 "내 제품답게". 계산기·SaaS 등 UI 제품이 늘수록 가치 상승.
2. **user-docs** — 사용자용 문서(README 사용 가이드, CHANGELOG). 현재
   docs 스킬은 개발자용 기술 문서 전담이라, 배포하는 제품이 생기면 분리 추가.
3. **youtube-automation / blog-automation** — 해당 프로젝트를 실전 진행하며
   검증된 절차가 생기면 그때 스킬로 승격 (검증 전 지식은 넣지 않는다).

✅ 완료: **docs** (v1.2.0) — 개발자용 기술 문서 4종 + drift 검사 + DECISIONS→ADR 파이프.

---

## 업데이트

리포 수정 → `plugin.json`의 version 올림 → push. 각 기기에서:

```
/plugin marketplace update dev-kit   # 카탈로그(로컬 클론) 갱신 — 이걸 빼먹으면 "not found"
/plugin update dev-kit               # 플러그인 갱신
```

마켓플레이스는 로컬 git 클론이라 `install`/`update`가 자동으로 원격을
당겨오지 않는다. version을 안 올리거나 marketplace update를 건너뛰면
캐시 때문에 변경이 반영되지 않는다. 헌법(CLAUDE.md.template)은 심볼릭
링크로 배치돼 있으므로 `git pull`만으로 즉시 반영된다 — 별도 재배치 불필요.

## 라이선스

MIT
