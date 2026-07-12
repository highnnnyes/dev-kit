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
/write-plan ──→ PLAN.md               ← stage → 2~5분 태스크, role 태그, [P]병렬 그룹
   ↓ (DECISIONS 없으면 대기 없이)
/execute-plan (메인 = 오케스트레이터, 직접 구현 안 함)
   │
   │  태스크마다:
   ├─→ builder (신선한 컨텍스트 + role 페르소나 주입) — 구현
   ├─→ reviewer (읽기 전용, 독립 컨텍스트) — PASS/FAIL 판정
   ├─→ PLAN.md 체크 + PROGRESS.md 기록 + git 커밋
   └─→ NEXT TASK로 다음 태스크 (반복)
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
| `commands/write-plan.md` | 설계 → PLAN.md 분해. 코드를 실제로 읽고 계획, 태스크마다 파일 경로·verify·role 필수, 아키텍처 결정은 DECISIONS로 분리 |
| `commands/execute-plan.md` | 실행 루프 오케스트레이션. 브리핑 작성, 병렬 디스패치, 리뷰 루프, 기록 |
| `agents/builder.md` | 태스크 1개를 신선한 컨텍스트에서 구현. 범위 밖 수정 금지, verify 통과 후에만 완료 선언, 막히면 BLOCKED 보고 |
| `agents/reviewer.md` | 읽기 전용 검증자. diff 스코프 한정, PASS/FAIL + BLOCKING/NON-BLOCKING 구분, PASS 시 다음 태스크 브리핑(NEXT TASK) 생성 |
| `CLAUDE.md.template` | **개발 헌법** (플러그인 외부 배치 필수 — 아래 설치 참조). 자동 라우팅, Karpathy 원칙, 책임 규정, 안전 가드레일 |

---

## 설치

### 1. 플러그인

```bash
# GitHub에 올린 경우 (권장 — 업데이트·다기기 동기화 용이)
/plugin install https://github.com/<username>/dev-kit

# 또는 로컬 테스트
claude --plugin-dir /path/to/dev-kit
```

### 2. 헌법 배치 (필수)

```bash
cp CLAUDE.md.template ~/dev/CLAUDE.md   # 모든 프로젝트의 공통 상위 폴더
```

**이 파일이 없으면**: 커맨드(`/dev-kit:write-plan` 등)는 작동하지만
자동 라우팅이 없어서 매번 수동으로 커맨드를 쳐야 하고, Karpathy 원칙·
가드레일도 적용되지 않는다. 플러그인은 "도구", CLAUDE.md는 "상시 규칙"이며
Claude Code 구조상 상시 규칙은 CLAUDE.md로만 주입된다.

### 3. 확인

```
/plugin           → dev-kit 표시 확인
/agents           → builder, reviewer 표시 확인
```

---

## 사용법

### 기본 — 그냥 요청하면 됨

```
> 보고서 앱에 PDF 내보내기 기능 추가해줘
```

자동 라우팅이 요청을 분류한다:

| 분류 | 조건 | 동작 |
|---|---|---|
| 계획 필요 | 여러 파일, 새 모듈, 설계 판단 | PLAN.md 생성 → 전체 출력 → 즉시 실행 |
| 진행 계속 | PLAN.md에 미완료 태스크 + "진행해" 류 | 미완료 지점부터 자동 재개 |
| 사소한 작업 | 한 파일, 자명한 수정 | 계획 없이 처리 + 리뷰만 |

애매하면 계획 생성 쪽으로 분류된다 (계획 과잉이 무계획보다 싸다).

### 실행이 멈추는 경우 (사용자 개입 지점)

1. **DECISIONS** — 계획에 아키텍처 결정이 필요하면 실행 전에 물어보고 대기
2. **3회 연속 FAIL** — 같은 태스크가 리뷰를 3번 통과 못 하면 중단·보고
3. **BLOCKED** — builder가 전제 붕괴를 발견하면 (파일 없음, 스펙 모순 등)
4. **파괴적 작업** — rm -rf, DROP TABLE, force-push, 프로덕션 배포 등은 항상 확인
5. **사용자 중단 지시**

### 실행 중 개입

계획이 출력된 뒤 실행 중에도 수정 지시가 가능하다:

```
> 1.3은 빼고 진행해
> Stage 2는 방식을 바꿔서 ...
```

PLAN.md를 갱신하고 이어간다. 승인 게이트 없이도 계획 교정이 가능한 구조.

### 수동 커맨드 (자동 라우팅 오버라이드)

```
/dev-kit:write-plan [설명]     # 계획만 만들고 실행 안 함
/dev-kit:execute-plan          # 실행만 (첫 미완료 태스크부터)
/dev-kit:execute-plan stage 2  # 특정 stage만
```

---

## PLAN.md 형식

`/write-plan`이 생성한다. 직접 써도 무방하다.

```markdown
# PLAN: PDF 내보내기
작성: 2026-07-12 · 상태: IN PROGRESS

## DECISIONS (사용자 결정 필요 — 비어있으면 생략)
- [ ] D1: PDF 라이브러리 — puppeteer(정확한 렌더링, 무거움) vs pdfkit(가벼움, 레이아웃 수동)

## Stage 1: 데이터 준비 — 완료 조건: export API가 JSON 반환
- [ ] 1.1 export 서비스 골격 · 파일: `services/export.ts` (신규) · role: backend · verify: 유닛테스트 통과
- [ ] 1.2 [P1] 템플릿 컴포넌트 · 파일: `components/PdfTemplate.tsx` (신규) · role: frontend · verify: 스토리북 렌더 확인
- [ ] 1.3 [P1] 테스트 픽스처 · 파일: `tests/fixtures/report.ts` (신규) · role: test · verify: import 에러 없음
```

- **role 태그**: 실행 시 builder에게 해당 전문가 페르소나가 주입된다
  (frontend/backend/db/test/infra/docs/general). 별도 에이전트 파일 불필요 —
  오케스트레이터가 태스크에 맞는 역할 지침을 브리핑에 즉석 작성한다.
- **[P그룹]**: 같은 번호끼리 병렬 실행. 조건: 상호 의존 없음 + 파일 안 겹침.
  동시 최대 3개 (토큰 소모가 병렬 수에 비례). 리뷰는 그룹 완료 후 순차.

---

## 기록 체계 (감사 추적)

| 파일 | 내용 | 용도 |
|---|---|---|
| `PLAN.md` | 뭘 할지 + 체크 상태 | 진행률 파악, 세션 재개 기준점 |
| `PROGRESS.md` | 태스크별 실행 일지 — 변경 내용, 검증 결과, FAIL 사유, 넘긴 사항 | 자리 비웠다 와서 훑기, 문제 역추적 |
| git 커밋 | 태스크당 1커밋 `[plan 1.2] 목표` | 태스크 단위 diff·bisect·롤백 |
| raw 트랜스크립트 | `~/.claude/projects/` (Claude Code 자동) | 브리핑/verdict 원문 디버깅용 |

---

## 토큰 관리

이 워크플로우는 태스크마다 서브에이전트를 띄우므로 단일 세션 대비 토큰을
많이 쓴다 (서브에이전트 다용 워크플로우는 수 배 소모 가능). 내장된 완화 장치:

- 자명한 소형 태스크는 오케스트레이터가 builder 없이 직접 처리
- 연속 소형 태스크 2~3개는 하나의 builder로 묶기 (verify는 개별 실행)
- 병렬 동시 상한 3
- 브리핑은 자족적 최소한으로 — 프로젝트 전체 맥락 주입 금지
- 리뷰어 스코프는 해당 태스크 diff만

토큰이 빠듯하면 [P] 그룹을 순차로 돌리라고 지시하면 된다 (속도↔토큰 트레이드오프).

## 튜닝 가이드

- **중단 조건 4(파괴적 작업)나 BLOCKED가 자주 걸림** → PLAN.md 태스크 정의가
  모호하다는 신호. 멈춘 지점의 질문을 보고 완료 조건을 구체화하라.
- **리뷰어가 너무 깐깐해서 루프가 김** → reviewer.md의 "확신 8/10 미만은
  NON-BLOCKING" 기준을 조정하라.
- **특정 프로젝트만 계획 승인 후 실행하고 싶음** → 그 프로젝트의 CLAUDE.md에
  "이 프로젝트는 계획 승인 후 실행" 한 줄 추가 (하위가 상위를 덮어씀).
- **에이전트가 만든 계획이 의도와 자주 어긋남** → dev/CLAUDE.md 라우팅 2번에서
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

## 업데이트

파일 수정 → `plugin.json`의 version 올림 → push → `/plugin update dev-kit`.
(version을 안 올리면 캐시 때문에 변경이 반영되지 않을 수 있다.)

## 라이선스

MIT
