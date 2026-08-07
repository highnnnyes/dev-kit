---
description: PLAN.md를 읽고 태스크 루프를 실행한다 — builder 구현 → reviewer 검증 → 체크 → 다음
---

프로젝트 루트의 PLAN.md를 읽고 미완료 태스크를 순서대로 실행하라.
당신(메인 에이전트)은 이 루프의 **오케스트레이터**다 — 직접 구현하지 않고
계획 상태 관리, 브리핑 작성, 서브에이전트 조율, 예외 처리만 한다.
이렇게 해야 메인 컨텍스트가 수십 태스크를 거쳐도 오염되지 않는다.

## 사전 체크
1. PLAN.md의 DECISIONS에 미결 항목이 있으면 실행하지 말고 사용자에게 결정을 요청하라.
   결정을 받으면 실행 시작 전에 `docs/decisions/NNN-제목.md`에 ADR로 기록하라
   (맥락/결정/근거/기각한 대안 — 10줄 이내, docs 스킬 형식). 결정의 맥락이
   채팅에서 증발하는 것을 막는다.
2. $ARGUMENTS로 특정 stage/task가 지정되면 그것만, 아니면 첫 미완료 태스크부터.

## 태스크 루프
각 태스크에 대해:

0. **일시정지 확인**: 착수 전에 프로젝트 루트의 `.dev-kit-pause` 파일 존재를
   확인한다. 존재하면 루프를 중단하고 진행 상황을 요약 보고한 뒤,
   "재개: `.dev-kit-pause` 삭제 후 '진행해'라고 지시"를 안내한다.
   태스크 중간에는 멈추지 않고 반드시 태스크 경계에서만 멈춘다.
   **stage 시작 기록**: 이 태스크가 해당 stage의 첫 태스크면 PROGRESS.md에
   `## [날짜시각] Stage N 시작 — base=<현재 HEAD sha>` 한 줄을 append한다 —
   stage-reviewer의 통합 diff 스코프가 이 sha를 사용한다.

1. **브리핑 작성**: builder가 신선한 컨텍스트에서 시작해도 바로 착수할 수 있게
   자족적인 브리핑을 만든다 — 태스크 목표, 파일 경로, verify 방법,
   이전 태스크의 NOTES에서 넘어온 제약. 프로젝트 전체 맥락을 쏟아붓지 마라.
   그 태스크에 필요한 것만.
   - 프로젝트에 ARCHITECTURE.md가 있으면 브리핑에 명시한다:
     "구조 파악은 ARCHITECTURE.md 먼저, 코드 탐색은 그다음" — builder의
     탐색 토큰을 절감한다.
   - **역할 주입**: 태스크의 role 태그에 맞는 전문가 페르소나를 브리핑 첫 줄에
     주입한다. 예: role: db → "당신은 DB 마이그레이션 전문가다. 스키마 변경 시
     롤백 경로를 항상 확보하라." / role: test → "당신은 테스트 엔지니어다.
     경계값과 에러 경로를 우선 커버하라." 역할별 상세 지침은 오케스트레이터가
     태스크 내용에 맞게 그때그때 작성한다 — 별도 에이전트 파일을 만들 필요 없다.
2. **builder 서브에이전트 호출** (브리핑 전달) → STATUS 수신.
   - **티어 라우팅**: tier=light면 builder-light를, 아니면 builder를 호출한다.
     builder-light가 BLOCKED를 반환하면 같은 태스크를 builder로 1회
     재시도하고, 그것도 실패하면 정상 FAIL 카운트에 넣는다. 승급 시
     사유 태그로 tier를 재판정한다: `[판단 필요]`면 애초에 오분류였던
     것이므로 PLAN.md의 tier를 standard로 재기입하고 TDD를 적용한다.
     `[verify 미통과]`면 기계적 태스크가 맞으므로 light를 유지한다.
   - **병렬 디스패치**: 같은 [P그룹] 태스크들은 각각의 builder를 동시에 띄운다.
     조건: (a) 파일이 서로 겹치지 않을 것 — 겹치면 순차로 강등,
     (b) 동시 최대 3개 — 토큰 소모가 병렬 수에 비례하므로 상한을 지킨다,
     (c) 그룹 전체가 끝난 후 리뷰로 넘어간다.
   - **병렬 그룹의 스코프 격리**: 그룹 완료 시점의 워킹트리에는 그룹 전체
     변경이 섞여 있다. 각 builder의 CHANGED 파일 목록을 수집해서:
     (a) 태스크별 reviewer 브리핑에 "스코프: `git diff -- <해당 파일들>`"로
     스코프를 못박는다, (b) 커밋도 같은 목록으로 `git add <해당 파일들>`
     부분 스테이징 후 커밋한다 — `git commit -a` 금지 (다른 태스크의
     미리뷰 변경이 섞여 들어간다), (c) FAIL 태스크의 변경은 스테이징하지
     않고 워킹트리에 남긴 채 재작업한다 — PASS 태스크만 커밋한다.
   - BLOCKED → 사유 태그로 분기: `[전제 붕괴]`(태스크 정의·전제 문제)면
     루프 중단, 사용자에게 사유와 함께 보고. `[verify 미통과]`(구현은 했으나
     verify 실패)면 해당 태스크의 정상 FAIL 카운트에 산입하고 실패 내용을
     브리핑에 추가해 재호출한다. (병렬 중이면 나머지 완료를 기다린 후 처리.)
3. **reviewer 서브에이전트 호출** (스코프: 이 태스크의 diff만) → VERDICT 수신.
   병렬 그룹은 태스크별로 순차 리뷰한다 (리뷰까지 병렬화하면 지적사항 반영이 꼬인다).
   [P] 그룹 내 태스크의 리뷰에서는 NEXT TASK를 생략한다
   (그룹 완료 후 마지막 리뷰만 NEXT TASK 포함).
   - **리뷰 2단 티어링**: 기본 호출은 model 파라미터를 생략한다(frontmatter의
     sonnet 적용). **sonnet이 FAIL이면** 같은 브리핑에 sonnet의 BLOCKING
     목록을 첨부해 reviewer를 `model: opus` 파라미터로 1회 재호출한다
     (파라미터가 frontmatter를 덮어쓰는 동작 — stage-reviewer 강등과 같은
     메커니즘, 방향만 승격). opus의 verdict가 최종이다:
     - opus PASS → 통과 (sonnet 오판 — 아래 승격리뷰 기록).
     - opus FAIL → 최종 FAIL. 재브리핑에는 opus의 BLOCKING을 사용한다.
     sonnet PASS는 승격 없이 그대로 최종 PASS다.
   - FAIL(최종 verdict 기준) → BLOCKING 사항을 브리핑에 추가해서 builder
     재호출. 같은 태스크 3회 FAIL이면 루프 중단, 보고. FAIL 카운트·시도
     횟수는 최종 verdict로만 센다 — 오판으로 뒤집힌 태스크는 시도 1회다.
   - PASS → 4로.
4. **체크 + 기록**: PLAN.md에서 해당 태스크를 [x]로 갱신하고, 다음 두 가지를 남긴다:
   - **PROGRESS.md** (프로젝트 루트, 없으면 생성)에 태스크당 한 블록 append.
     첫 줄은 아래 구조화 형식을 **그대로** 지킨다 (통계 집계가 이 라인을 grep한다):
     ```
     ## [날짜시각] Task N.M — [PASS|FAIL후PASS|BLOCKED] · 시도 X회 · builder=[모델] · reviewer=[sonnet|sonnet→opus] · tier=[light|standard]
     - 변경: [builder CHANGED 요약]
     - 검증: [reviewer VERIFIED 요약]
     - FAIL사유: [BLOCKING 요약 한 줄 + 유형(컨벤션 위반|기능 결함|verify 미충족|보안|기타)]
     - 넘김: [builder NOTES / reviewer NON-BLOCKING]
     ```
     FAIL이 한 번이라도 있었던 태스크는 `- FAIL사유:` 줄을 반드시 포함한다
     (1회 통과면 생략). builder=에는 실제 투입된 에이전트의 모델을 적는다
     (light→builder 승급 시 최종 통과시킨 쪽). reviewer=에는 승격 발생 시
     `sonnet→opus`를 적고 다음 줄을 추가한다 (오판율 추적용):
     `- 승격리뷰: [PASS로 뒤집음(오판)|FAIL 유지] + 사유 한 줄`
   - **git commit** 태스크당 1회. 메시지: `[plan 1.2] 태스크 목표 한 줄` +
     본문에 verify 결과. 이러면 태스크 단위로 diff·bisect·롤백이 가능하다.
   **stage 경계 처리**: 한 stage의 모든 태스크가 완료되면 **stage-reviewer**
   (통합 검증)를 호출한다 — 스코프: stage 시작 커밋..HEAD 통합 diff +
   PLAN.md의 stage 완료 조건 + PROGRESS.md의 해당 stage 기록.
   stage 시작 커밋은 PROGRESS.md의 `Stage N 시작 — base=` 라인에서 읽어
   브리핑에 sha로 명시해 전달한다.
   - **모델 선택**: 기본은 Task 호출 시 `model: opus`를 **명시**한다
     (frontmatter의 fable을 강등). 아래 승격 조건 중 하나라도 해당하면
     model 파라미터를 **생략**해 frontmatter의 fable이 적용되게 한다:
     - 해당 stage가 인증·결제·데이터 마이그레이션·외부 시스템 연동·
       되돌리기 어려운 변경을 포함
     - PLAN.md의 DECISIONS 항목이 그 stage에서 구현됨
   - PASS → stage 완료 처리 후 다음 stage로 진행.
   - FAIL → PROPOSED TASKS를 PLAN.md에 보완 태스크로 추가하고 정상 루프
     (builder→reviewer)로 처리한 뒤 stage-reviewer를 1회만 재호출한다.
     두 번째도 FAIL이면 루프를 멈추고 사용자에게 보고한다.
   - 생략: stage 태스크가 2개 이하이거나 문서 전용 stage.
     **단, 오케스트레이터가 직접 처리한 태스크(경량화 규칙)가 하나라도
     있으면 생략 불가** — 직접 처리분은 stage-reviewer가 유일한 독립 검증이다.
   - 결과를 PROGRESS.md에도 동일 구조화 형식으로 기록:
     `## [날짜시각] Stage N 통합검증 — [PASS|FAIL] · FINDINGS X건 · model=[opus|fable]`
     model=에는 **실제 투입된 모델**을 적는다. fable 승격 시 다음 줄에
     `- 승격사유: [해당 승격 조건]`을 추가한다.
   - **롤링 요약 (통합검증 기록 후 마지막 절차)**: PROGRESS.md가 stage 수에
     비례해 커지는 것을 막는다. 반드시 stage-reviewer 호출·기록이 **끝난 뒤**
     수행한다 (stage-reviewer는 현 stage 전문을 읽어야 한다):
     1. 종료된 stage의 태스크 블록들과 `Stage N 시작 — base=` 라인 원문을
        `PROGRESS.archive.md`(프로젝트 루트, 없으면 생성)에 그대로 append.
     2. PROGRESS.md에서 해당 블록들을 요약 한 줄로 치환:
        `## Stage N 요약 — 태스크 X개 · FAIL Y건([유형 요약]) · 통합검증 [PASS|FAIL후PASS] · 결정: [주요 결정 or 없음]`
        (통합검증 라인은 요약에 흡수하고 삭제한다.)
     3. 단, **최근 5개 태스크 블록은 stage 소속과 무관하게 전문 유지**한다 —
        다음 태스크 브리핑의 NOTES/NON-BLOCKING 인계에 필요하다.
5. reviewer의 NEXT TASK 브리핑과 builder의 NOTES를 다음 태스크 브리핑에 반영하고 1로.

## 경량화 규칙 (토큰 관리 — 헌법 §4 기본 검증 루프의 명시적 예외)
- 자명한 소형 태스크(설정 한 줄, 자명한 오타 수준)는 builder 없이 직접 처리해도 된다.
  단, 직접 처리한 태스크는 stage 경계의 stage-reviewer 브리핑에 **목록으로
  명시**해서 해당 diff의 태스크 레벨 검증을 받는다 (이때 stage-reviewer의
  생략 조건은 무효). 이 부류는 성격상 tier=light이므로 TDD(§3, standard
  한정) 대상이 아니다 — 판단이 들어가는 태스크는 직접 처리 대상이 아니다.
- 연속된 소형 태스크 2~3개는 하나의 builder 브리핑으로 묶어도 된다.
  단, verify는 태스크별로 전부 실행한다.

## 중단 조건 (CLAUDE.md §4와 동일)
(a) 태스크 3연속 FAIL / (b) builder BLOCKED(`[전제 붕괴]` 한정 —
`[verify 미통과]`는 FAIL 카운트로 흡수) / (c) 전 태스크 완료
/ (d) 다음 태스크가 아키텍처 결정·파괴적 작업·요구사항 불명 포함
/ (e) 사용자 중단 지시 / (f) stage-reviewer 2회 연속 FAIL
/ (g) `.dev-kit-pause` 파일 존재.

중단·완료 시 보고: 완료 태스크 수, 남은 태스크, 발생 이슈, 리뷰어 NON-BLOCKING 누적 목록.

추가로 **검증 통계** 섹션을 포함한다 (PROGRESS.md **+ PROGRESS.archive.md**의
구조화 라인에서 집계한다 — 롤링 요약으로 압축된 stage의 원본 라인은 archive에 있다):
- 총 태스크 / 1회 통과 / 재시도 발생(비율%) / BLOCKED
- tier별 분포 (light/standard 각 몇 건, light 승급 건수)
- FAIL 사유 상위 유형 (컨벤션 위반·기능 결함·verify 미충족·보안·기타)
- 리뷰 승격 건수 / 오판율 (승격 중 opus가 PASS로 뒤집은 비율 —
  높으면 sonnet이 과하게 깐깐, 승격이 0에 수렴하면 느슨할 가능성)
