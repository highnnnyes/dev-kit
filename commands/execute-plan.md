---
description: PLAN.md를 읽고 태스크 루프를 실행한다 — builder 구현 → reviewer 검증 → 체크 → 다음
---

프로젝트 루트의 PLAN.md를 읽고 미완료 태스크를 순서대로 실행하라.
당신(메인 에이전트)은 이 루프의 **오케스트레이터**다 — 직접 구현하지 않고
계획 상태 관리, 브리핑 작성, 서브에이전트 조율, 예외 처리만 한다.
이렇게 해야 메인 컨텍스트가 수십 태스크를 거쳐도 오염되지 않는다.

## 사전 체크
0. **모델 확인 (세션당 루프 시작 시 1회)**: 시스템 프롬프트에서 자기 모델을
   확인한다. **fable이면 루프를 시작하지 않고** 보고하라: "실행 루프
   오케스트레이션은 opus로 충분하다 (판단 작업은 전부 서브에이전트 위임 —
   README 모델 티어링). `/model opus` 후 '진행해', fable 유지 의도면
   'fable로 진행해'." 명시적 우회 지시를 받으면 그대로 진행한다.
   태스크 경계에서는 재확인하지 않는다.
1. PLAN.md의 DECISIONS에 미결 항목이 있으면 실행하지 말고 사용자에게 결정을 요청하라.
   결정을 받으면 실행 시작 전에 `docs/decisions/NNN-제목.md`에 ADR로 기록하라
   (맥락/결정/근거/기각한 대안 — 10줄 이내, docs 스킬 형식). 결정의 맥락이
   채팅에서 증발하는 것을 막는다.
2. $ARGUMENTS로 특정 stage/task가 지정되면 그것만, 아니면 첫 미완료 태스크부터.
   재개 시 PROGRESS.md 최상단의 `## RESUME` 블록이 있으면 그것부터 읽는다 —
   전체 기록을 훑지 않아도 다음 태스크·미결 사항·남은 워크트리를 알 수 있다.
3. **워크트리 정리**: `git worktree prune`을 1회 실행한다 — 이전 실행에서
   정리 실패로 남은 고아 워크트리를 회수한다.
4. **워크트리 선언 확인**: 프로젝트 CLAUDE.md의 `worktree:` 선언을 읽는다
   (`shared-env` | `isolated-env` | `off`). **선언이 없으면 `off`로 간주한다.**
   `off`면 [P] 그룹을 병렬로 돌리지 않고 **순차 실행으로 강등**한다 —
   환경 공유 가능 여부는 스택마다 다르고, 잘못 켜면 의존성 없는 워크트리에서
   verify가 거짓 실패하기 때문에 기본값이 off다.
5. **실행 모드 확인**: PLAN.md 헤더의 `mode: S|A|B` 라인을 읽는다.
   **헤더가 없으면 S로 간주한다** (하위 호환).
   - **S** — 현행 순차: [P] 태그가 있어도 순차 강등한다.
   - **A** — 단일 세션 병렬: [P] 그룹을 워크트리 격리로 병렬 실행
     (`worktree:` 선언 조건은 그대로 유지 — 미선언이면 순차 강등) +
     아래 "mode A 병렬 강화" 적용. Stage 0(계약)이 있으면 반드시 먼저,
     직렬로 완료한다.
   - **B** — headless 트랙 병렬: **PLAN.md 헤더에 사용자 승인이 기록된
     경우에만** 아래 "mode B 런처"로 진행한다. 승인 기록이 없으면 A로
     간주하고 사유를 보고한다.
   $ARGUMENTS가 `track <이름>`이면 이 세션은 mode B의 **트랙 세션**이다 —
   자기 워크트리의 트랙 스코프 PLAN만 실행한다 (mode B 런처의 트랙 규칙 적용).

## 실행 중 CLAUDE.md 수정 금지 (캐시 접두사 보존) [엄격]
execute-plan 루프가 도는 동안 dev 루트 헌법과 프로젝트 CLAUDE.md를 수정하지
않는다. 이 파일들은 모든 서브에이전트 호출의 프롬프트 캐시 접두사에 포함되므로,
중간에 수정하면 그 이후 남은 태스크 전부의 캐시가 무효화된다 — 호출마다 고정
오버헤드를 정가로 재지불하게 된다. 수정이 필요하면 해당 태스크를 stage
마지막으로 미루고, 수정 후에는 stage를 끝내고 새 세션을 권고한다
(RESUME 블록 갱신 포함 — stage 경계 처리의 세션 재시작 권고와 동일 절차).

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
     주입한다. PLAN.md에 `## ROLES` 블록이 있으면 해당 role의 지침을 **그대로
     복사**한다 — 태스크마다 재작성하지 않는다 (지침 생성은 write-plan 시점
     1회). 블록이 없는 구버전 PLAN.md면 기존대로 즉석 작성한다.
     예: role: db → "당신은 DB 마이그레이션 전문가다. 스키마 변경 시
     롤백 경로를 항상 확보하라." 별도 에이전트 파일을 만들 필요는 없다.
2. **builder 서브에이전트 호출** (브리핑 전달) → STATUS 수신.
   - **스코프 파일 [엄격]**: builder 디스패치 **직전**, 프로젝트 루트
     `.dev-kit-scope`에 이번에 디스패치하는 모든 태스크의 대상 파일 경로를
     한 줄에 하나씩 쓴다 — PreToolUse 훅이 이 목록 밖 Edit/Write를 deny한다.
     builder(들)가 전부 반환하면 **즉시 삭제**한다 (이후의 오케스트레이터
     자신의 PLAN/PROGRESS 기록이 막히지 않게). 재작업 재호출 시에도 동일하게
     생성·삭제한다. 최초 1회 프로젝트 `.gitignore`에 `.dev-kit-scope`를
     추가한다. 한계: 같은 디스패치에 묶인 태스크 **간** 교차는 이 목록으로
     못 막는다(둘 다 목록에 있으므로) — 그 층은 아래 워크트리 격리가 담당한다.
   - **티어 라우팅**: tier=light면 builder-light를, 아니면 builder를 호출한다.
     builder-light가 BLOCKED를 반환하면 같은 태스크를 builder로 1회
     재시도하고, 그것도 실패하면 정상 FAIL 카운트에 넣는다. 승급 시
     사유 태그로 tier를 재판정한다: `[판단 필요]`면 애초에 오분류였던
     것이므로 PLAN.md의 tier를 standard로 재기입하고 TDD를 적용한다.
     `[verify 미통과]`면 기계적 태스크가 맞으므로 light를 유지한다.
   - **TDD 2단 디스패치 [엄격] — tier=standard 코드 태스크**: builder 호출을
     red/green 두 단계로 나눈다. TDD 증거는 서술 기록이 아니라 **git 커밋과
     오케스트레이터의 독립 실행**으로 남긴다 — 커밋과 실행 결과는 위조할 수 없다.
     1. **red 디스패치**: 브리핑 첫 줄에 `[red]`를 명시하고 "verify의 테스트만
        작성, 구현 금지"를 지시한다. builder 반환 후 CHANGED 한정 `git add` →
        `[plan N.M][red] 테스트 추가` 커밋 (커밋은 오케스트레이터가 한다).
     2. **red 확인 (커밋 직후)**: 오케스트레이터가 이 태스크의 verify를 직접
        실행해 **실패를 직접 확인**하고, 4의 PROGRESS.md 기록에
        `red: CONFIRMED`로 남긴다. 실패하지 않으면(처음부터 green) builder에게
        테스트 재작성을 지시한다 — 이 재작성도 3회 FAIL 카운트에 산입하고
        유형은 `verify-gate`로 기록한다. 이 실행은 아래 "verify 선행 게이트"의
        안전 제약을 그대로 상속한다 — 별도의 임의 명령 실행 권한이 아니다.
     3. **green 디스패치**: 브리핑 첫 줄에 `[green]`을 명시하고 "커밋된
        테스트를 통과시키는 최소 구현"을 지시한다. builder 반환 후 CHANGED
        한정 `git add` → `[plan N.M][green] 구현` 커밋.
     대상 아님(tier=light, role=docs, 테스트 인프라 최초 셋업)은 기존 단일
     디스패치. 워크트리 병렬 흐름에서도 동일하게 적용한다 — 커밋·red 확인
     전부 해당 워크트리 안에서 수행하고, reviewer 스코프는 `git diff HEAD~2`.
   - **병렬 디스패치 — 워크트리 격리 (worktree: shared-env|isolated-env
     선언 시에만)**: 같은 [P그룹] 태스크들을 태스크마다 전용 워크트리에서
     동시에 실행한다. 동시 최대 3개 — 토큰 소모가 병렬 수에 비례한다.
     `worktree: off`(또는 선언 없음)면 그룹을 **순차로 강등**해 메인 트리에서
     일반 흐름으로 처리한다. **그룹에 의존성(패키지 설치·잠금 파일) 변경
     태스크가 있으면 shared-env여도 그룹 전체를 순차로 강등한다** — 동일
     환경에 동시 설치는 경합한다.
     1. 태스크마다 `git worktree add <dev 루트>/.worktrees/<project>/<task-id>
        -b wt/<task-id>`. **반드시 dev 루트 아래여야 한다** — 그래야 공통
        헌법(`<dev 루트>/CLAUDE.md`)이 상속된다. `/tmp` 등 바깥에 만들면
        에이전트가 규칙 없이 돈다. shared-env면 메인 트리 환경 재사용 설정
        (예: uv면 `UV_PROJECT_ENVIRONMENT=<메인트리>/.venv`), isolated-env면
        프로젝트 CLAUDE.md의 `worktree-env-setup:` 명령을 워크트리에서
        실행한다. dev 루트가 git 리포면 `.worktrees/`를 dev 루트
        `.gitignore`에 추가한다.
     2. builder를 **해당 워크트리 경로에서** 실행한다 (브리핑에 작업 디렉토리
        명시). **[P] 워크트리 태스크(mode S/A)는 PLAN.md·PROGRESS.md를 읽지도
        쓰지도 않는다** — 이 파일들은 메인 트리 소유이고, 워크트리 브랜치가
        건드리면 머지마다 충돌한다. 기록은 오케스트레이터가 메인 트리에서만
        한다. (mode B의 **트랙 워크트리는 예외** — 트랙이 자기 워크트리의
        트랙 PROGRESS.md를 소유·기록한다. 아래 mode B 런처 참조.)
     3. builder 반환 후 워크트리 안에서 `git add <CHANGED 파일들>` → 커밋
        (태스크당 1커밋 — TDD 2단 디스패치 태스크는 red/green 2커밋, 위 절차를
        워크트리 안에서 수행). 워크트리에는 이 태스크의 변경뿐이지만 CHANGED
        한정 원칙은 유지한다. (커밋되므로 신규 파일 노출용 `git add -N`은
        워크트리 흐름에서는 불필요하다 — diff가 커밋 경계로 잡힌다.)
        커밋 후 **verify 선행 게이트**(아래)를 해당 워크트리 안에서 실행한다.
     4. reviewer를 **워크트리 안에서** 실행한다 — 스코프:
        `git diff HEAD~1 -- <파일들>` (TDD 2단 태스크는 `git diff HEAD~2 --
        <파일들>`). 워크트리에는 남의 변경이 물리적으로 없으므로 스코프가
        자동 보장된다. FAIL 시 같은 워크트리에서 수정 후 `git commit --amend`로
        커밋 수를 유지하고(TDD 태스크는 `[green]` 커밋에 amend) 재리뷰한다.
     5. 그룹 전체 PASS 후 아래 "그룹 경계 처리"(머지 + 통합 검증 게이트)로
        넘어간다. BLOCKED·3회 FAIL 태스크의 워크트리는 **제거하지 않는다** —
        경로를 보고에 포함해 사용자가 직접 확인할 수 있게 한다.
   - BLOCKED → 사유 태그로 분기: `[전제 붕괴]`(태스크 정의·전제 문제)면
     루프 중단, 사용자에게 사유와 함께 보고. `[verify 미통과]`(구현은 했으나
     verify 실패)면 해당 태스크의 정상 FAIL 카운트에 산입하고 실패 내용을
     브리핑에 추가해 재호출한다. (병렬 중이면 나머지 완료를 기다린 후 처리.)

   **verify 선행 게이트 [엄격] — reviewer 호출 전 필수**: builder가 완료
   (STATUS: DONE)를 보고하면 reviewer를 호출하기 **전에** 오케스트레이터가
   PLAN.md에 명시된 이 태스크의 verify 명령을 직접 1회 실행한다. builder가
   보고한 verify 결과는 참고 정보일 뿐 — **진실의 원천은 항상 오케스트레이터의
   독립 실행 결과다** (자기 보고 조작·환각 원천 차단).
   - **실패** → **reviewer를 호출하지 않는다** (실패 라운드당 리뷰 호출 1회
     절약). 실패 출력의 마지막 20줄만 첨부해 builder에게 재시도 브리핑을
     보낸다. 이 실패도 같은 태스크의 3회 FAIL 카운트에 포함하고, PROGRESS.md에
     `FAIL(verify-gate)` 유형으로 기록한다.
   - **성공** → 리뷰 브리핑에 `verify: PASS (orchestrator-run)` 한 줄을
     포함하고 reviewer를 호출한다.
   - 리뷰 FAIL 후 재작업의 재검증도 이 게이트부터 다시 시작한다.
   - **[엄격] 절차형 verify 허용 목록 (열거형 — 이 2종뿐)**:
     ① role=docs의 "drift 스캔 통과", ② harden의 "증거 칸 충족".
     이 2종만 오케스트레이터가 절차로 직접 수행해 판정하고, 통과 시 같은
     형식(`verify: PASS (orchestrator-run)`)으로 브리핑한다. **목록 밖의
     비-셸 verify는 절차형으로 간주하지 않는다** — 게이트 정지 대상으로
     처리해 태스크 경계에서 멈추고 사용자에게 확인을 요청한다 ("절차형"
     라벨링을 통한 게이트 우회 차단). 목록 추가는 프로젝트 CLAUDE.md
     오버라이드 대상이 아니며 **헌법 개정(dev-kit 파일 수정)으로만 가능하다.**

   **게이트 안전 제약 [엄격] — 게이트 로직보다 항상 우선**: verify 선행
   게이트(및 red 확인)는 **새로운 자동 실행 경로**이므로 다음이 게이트
   로직보다 상위 규칙이다.
   - 오케스트레이터가 자동 실행할 수 있는 verify는 **패키지/빌드 스크립트
     형태만이다**: `npm run *`, `pnpm *`, `yarn *`, `make *`, `pytest`,
     `go test`, `cargo test`, `tsc --noEmit` 및 프로젝트 CLAUDE.md에
     명시적으로 allowlist된 명령. 이 목록 밖의 verify는 실행하지 않고
     태스크 경계에서 멈춰 사용자에게 확인을 요청한다.
   - verify 문자열에 다음 패턴이 포함되면 **allowlist 여부와 무관하게 자동
     실행 금지**: `rm`, `drop`, `truncate`, `delete`, `reset`, `migrate`,
     `push`, `deploy`, `curl`/`wget`, 파이프·`&&`·`;` 연쇄, 리다이렉션(`>`).
     헌법 §5(파괴적 명령 확인)가 이 게이트에도 그대로 적용된다 —
     "verify 게이트니까"는 확인 생략 사유가 아니다.
   - red 확인 실행(TDD 2단 디스패치의 2)도 동일한 verify 명령의 재실행이므로
     위 제약을 그대로 상속한다. 별도의 임의 명령 실행 권한을 만들지 않는다.
   - 이 게이트는 Claude Code의 permission rules를 **우회하지 않는다.**
     settings.json의 deny rule(시크릿 읽기 차단 등)과 파괴적 명령 확인
     프롬프트는 게이트 실행에도 동일하게 걸린다 — "프롬프트가 실행하라고
     했으므로 확인 생략" 해석은 금지다.

3. **reviewer 서브에이전트 호출** (스코프: 이 태스크의 diff만) → VERDICT 수신.
   - **리뷰 입력 제한 [엄격]**: reviewer 브리핑에는 다음 네 가지만 담는다 —
     ① 태스크 정의(PLAN.md의 해당 태스크 줄 원문), ② diff 스코프 지정
     (TDD 2단 태스크는 `git diff HEAD~2 -- <파일들>`, 그 외는
     `git diff -- <파일들>`), ③ 오케스트레이터 verify 결과 1줄
     (`verify: PASS (orchestrator-run)`), ④ 프로젝트 CLAUDE.md(자동 상속 —
     별도 주입 불필요). PROGRESS.md·설계 문서·이전 태스크 내역 주입은
     금지한다 — 판정에 필요한 최소 입력이 리뷰 토큰과 편향을 동시에 줄인다.
   - **신규 파일 스코프 확보 (호출 직전 [엄격] — 커밋 전 리뷰 흐름 한정)**:
     TDD 2단 디스패치 태스크는 이 절차가 불필요하다 — red/green 커밋으로
     신규 파일이 diff에 이미 노출된다. 커밋 전에 리뷰하는 그 외 태스크
     (tier=light, role=docs 등)만 해당: builder의 CHANGED 파일
     목록에 대해 `git add -N <CHANGED 파일들>`을 실행한다(intent-to-add).
     untracked 신규 파일은 git diff에 나타나지 않아, 리뷰어가 신규 테스트
     파일을 못 보고 "테스트 없음"으로 오판하거나 추적표의 부재 판정 증거가
     거짓이 된다. 반드시 CHANGED 목록으로 한정한다 — `git add -N .`은 병렬
     그룹에서 남의 태스크 파일까지 등록해 스코프를 오염시킨다.
     실측: intent-to-add 파일은 `git add <다른 파일> && git commit`의 부분
     스테이징 커밋에 딸려 들어가지 않는다(워킹트리에 `A`로 남는다). 단
     `git commit -a`는 딸려 보내므로 **금지한다** — 리뷰 안 된 변경이 섞여
     들어간다. 커밋은 항상 CHANGED 목록 한정 `git add <파일들>`로 스테이징한다.
     이 명령은 **오케스트레이터가 실행한다** — 읽기 전용인 reviewer에게
     시키지 않는다. (워크트리 병렬 흐름에서는 커밋 후 리뷰이므로 이 절차가
     불필요하다 — 신규 파일이 커밋에 포함되어 diff에 이미 노출된다.)
   **mode A 병렬 강화** (mode A + worktree 선언 시):
   - **리뷰 병렬화**: reviewer는 읽기 전용 + diff 스코프 독립(각자 워크트리)
     이므로 [P] 그룹의 리뷰를 **병렬로 디스패치한다**. FAIL 재작업·재리뷰는
     해당 태스크의 워크트리 안에서 독립적으로 돌므로 지적사항 반영이 다른
     태스크와 꼬이지 않는다. (mode S의 순차 흐름에서는 해당 없음 —
     메인 트리 공유라 순차 리뷰 유지.)
   - **인터리빙 스케줄링**: [P] 그룹 단위로 전원 완료를 기다리지 않는다 —
     "의존이 충족된 태스크 풀"에서 동시 슬롯(상한 3, 기존 값 유지)을 상시
     채운다. 한 태스크가 리뷰 대기 중이면 다른 태스크가 슬롯을 사용한다.
     단 메인 트리 직렬 태스크는 동시에 1개만(작업 트리 공유), 그룹 머지와
     B-5 통합 검증 게이트는 그룹 전 태스크 PASS 시점에 그대로 수행한다.
   - **verify 선행 게이트·리뷰 밀도는 병렬에서도 태스크별로 동일 적용된다** —
     병렬이라는 이유로 게이트·red 확인·리뷰를 낮추거나 묶지 않는다.
   - **리뷰 2단 티어링**: 승격 조건은 둘이다.
     - **(1) 사후 승격**: 기본 호출은 model 파라미터를 생략한다(frontmatter의
       sonnet 적용). **sonnet이 FAIL이면** opus로 승격 재검증한다.
     - **(2) 사전 승격 [엄격]**: 태스크에 `risk: high` 태그가 있으면 FAIL
       여부와 무관하게 **처음부터 `model: opus`로 리뷰한다** (sonnet 호출
       자체를 건너뛴다). write-plan이 요구사항에 **수치·경계·개수 조건,
       보안, 데이터 변형/삭제, 동시성**이 포함된 태스크에 이 태그를 달고,
       여기서 그 태그로 라우팅한다. 태그가 없어도 브리핑의 요구사항에 이
       조건들이 명백히 보이면 사전 승격하고 PROGRESS.md에 사유를 남긴다.
       근거: (1)만으로는 약한 모델이 놓쳐서 PASS한 결함이 승격을
       트리거하지 못한다 — 거짓 PASS는 사후 승격의 사각지대다.
     사후 승격 시에는 같은 브리핑에 sonnet의 BLOCKING 목록을 첨부해
     reviewer를 `model: opus` 파라미터로 1회 재호출한다
     (파라미터가 frontmatter를 덮어쓰는 동작 — stage-reviewer 강등과 같은
     메커니즘, 방향만 승격). opus의 verdict가 최종이다:
     - opus PASS → 통과 (sonnet 오판 — 아래 승격리뷰 기록).
     - opus FAIL → 최종 FAIL. 재브리핑에는 opus의 BLOCKING을 사용한다.
     sonnet PASS는 승격 없이 그대로 최종 PASS다.
   - FAIL(최종 verdict 기준) → BLOCKING 사항을 브리핑에 추가해서 builder
     재호출. TDD 2단 태스크는 수정분을 CHANGED 한정 `git add` 후 `[green]`
     커밋에 amend한다. 수정 후 재검증은 verify 선행 게이트부터 다시 거쳐
     **다시 sonnet 기본 호출부터** 시작한다 —
     사후 승격은 라운드마다 독립이며, 직전 라운드가 opus였다는 이유로 opus를
     이어 쓰지 않는다. 단 **사전 승격(risk: high)은 태스크의 속성**이므로
     모든 라운드에서 opus를 유지한다. 같은 태스크 3회 FAIL이면 루프 중단, 보고. FAIL 카운트·시도
     횟수는 최종 verdict로만 센다 — 오판으로 뒤집힌 태스크는 시도 1회다.
   - PASS → 4로.
4. **체크 + 기록**: PLAN.md에서 해당 태스크를 [x]로 갱신하고, 다음 두 가지를 남긴다:
   - **PROGRESS.md** (프로젝트 루트, 없으면 생성)에 태스크당 한 블록 append.
     첫 줄은 아래 구조화 형식을 **그대로** 지킨다 (통계 집계가 이 라인을 grep한다):
     ```
     ## [날짜시각] Task N.M — [PASS|FAIL후PASS|BLOCKED] · 시도 X회 · builder=[모델|by=orchestrator] · reviewer=[sonnet|sonnet→opus|opus(사전승격)|미호출] · tier=[light|standard] · risk=[normal|high]
     - 변경: [builder CHANGED 요약]
     - 검증: [reviewer VERIFIED 요약 + 오케스트레이터 verify 게이트 결과]
     - red: [CONFIRMED (orchestrator-run)|재작성 N회 후 CONFIRMED] (TDD 2단
       디스패치 태스크만 — 그 외 태스크는 이 줄 생략)
     - 리뷰명령: [reviewer VERIFIED의 Bash 명령 목록을 **그대로** 옮겨 적는다 —
       요약·축약 금지. 계측이 로그에 남아야 스코프 준수와 읽기 전용 준수를
       사후 검증할 수 있다]
     - 파괴적명령: [builder DESTRUCTIVE 행을 그대로 전재 — "없음"도 그대로 적는다]
     - FAIL사유: [BLOCKING 요약 한 줄 + 유형(컨벤션 위반|기능 결함|verify 미충족|보안|verify-gate|기타)]
       (verify 선행 게이트·red 확인에서 걸린 실패는 유형 `verify-gate` —
       BLOCKING 요약 자리에 실패한 verify 명령과 결과 한 줄)
     - 넘김: [builder NOTES / reviewer NON-BLOCKING]
     ```
     FAIL이 한 번이라도 있었던 태스크는 `- FAIL사유:` 줄을 반드시 포함한다
     (1회 통과면 생략). builder=에는 실제 투입된 에이전트의 모델을 적는다
     (light→builder 승급 시 최종 통과시킨 쪽). reviewer=에는 사후 승격 발생 시
     `sonnet→opus`를 적고 다음 줄을 추가한다 (오판율 추적용):
     `- 승격리뷰: [PASS로 뒤집음(오판)|FAIL 유지] + 사유 한 줄`
     사전 승격(risk: high)은 `opus(사전승격)`으로 적고 승격리뷰 줄 대신
     다음 줄을 추가한다: `- 사전승격사유: [PLAN.md risk: high | 태그 없음 —
     발견한 조건 한 줄]`. 오판율 통계는 사후 승격만 집계 대상이다.
     **오케스트레이터가 직접 처리한 태스크(경량화 규칙)는 builder= 자리에
     `by=orchestrator`를 적는다** — stage-reviewer 생략 조건 판정을 로그로
     검증 가능하게 하기 위한 필드다(아래 stage 경계 처리 참조).
   - **git commit** 태스크당 1회. 메시지: `[plan 1.2] 태스크 목표 한 줄` +
     본문에 verify 결과. 이러면 태스크 단위로 diff·bisect·롤백이 가능하다.
     **TDD 2단 태스크는 이미 `[red]`/`[green]` 2커밋이 있으므로 새 커밋을
     만들지 않는다** — PLAN.md 체크·PROGRESS.md 갱신을 `[green]` 커밋에
     amend로 흡수한다 (메시지 본문에 오케스트레이터 verify 게이트 결과 추가.
     push 전 로컬 커밋이므로 amend는 안전하다).
     **[엄격] 이 리뷰 PASS 후 amend로 수정 가능한 파일은 PLAN.md·PROGRESS.md
     둘로 한정한다.** amend 직전 스테이징 diff(`git diff --cached --name-only`)
     에 그 외 파일이 포함되면 amend를 실행하지 말고 루프를 중단해 사용자에게
     보고한다 — 리뷰어가 판정한 diff와 최종 커밋의 동일성 보장이 근거다
     (기록 파일만이 판정 대상 밖이다). 리뷰 FAIL 후 수정분 amend(3의 재작업
     흐름)는 재검증 **전**이라 이 제한의 대상이 아니다 — 재리뷰가 그 diff를
     다시 판정한다. 워크트리 소유권 스코프:
     - **mode S/A의 [P] 워크트리 태스크**: PLAN.md·PROGRESS.md가 메인 트리
       소유라 이 amend 규칙의 대상이 아니다 — 워크트리의 `[green]`은 그대로
       두고, 기록은 그룹 머지 후 오케스트레이터가 메인 트리에서 남긴다.
     - **mode B의 트랙 워크트리**: 트랙이 자기 워크트리의 **트랙 PROGRESS.md를
       소유·기록**하므로, amend 한정 규칙(PLAN/PROGRESS만)이 트랙 로컬
       PROGRESS.md에 **동일 적용된다**. 메인 PROGRESS.md에는 통합 스테이지에서
       트랙 요약만 병합 기록한다 (mode B 런처의 기록 규칙 참조).
   **그룹 경계 처리 (워크트리 병렬 그룹 한정)**: 그룹 전체 PASS 후:
   1. 오케스트레이터가 메인 트리에서 `wt/<task-id>` 브랜치들을 **순차 머지**
      한다. 충돌 발생 시 `git merge --abort` 후 루프를 중단하고 충돌 파일과
      워크트리 경로를 사용자에게 보고한다 — [P] 그룹은 파일 비중첩이
      조건이므로 충돌은 그룹 편성 오류 신호다.
   2. **머지 후 통합 검증 게이트 [엄격]**: 그룹의 모든 태스크 verify 명령을
      **메인 트리에서** 다시 실행한다 — 오케스트레이터가 직접 실행하며 모델
      호출은 없다(비용은 테스트 실행 시간뿐). 근거: 워크트리 verify는 격리
      상태에서만 돌았고, 머지된 결과는 이 게이트 전까지 아무도 검증하지 않은
      상태다. stage-reviewer는 개별 태스크 diff 재리뷰 금지이고 stage 경계는
      머지보다 뒤라 이 구멍을 메우지 못한다.
      **그룹 크기 1이면 생략한다** — 머지 대상이 하나면 격리 상태 = 통합 상태다.
      - 전부 통과 → `git worktree remove <경로>` + `git branch -d wt/<task-id>`
        후 다음으로. remove 실패 시 **경고만 남기고 진행한다** (다음 실행
        시작 시의 `git worktree prune`이 고아를 회수한다 — 정리 실패는 루프를
        멈추지 않는다). 실행한 verify 명령과 결과를 PROGRESS.md에 전재한다
        (v1.7 명령 기록 원칙).
      - 하나라도 실패 → **통합 실패**: 워크트리는 제거하지 않는다(원인
        추적용 — 경로를 보고에 포함). 보완 태스크를 PLAN.md에 추가하고 정상
        루프(builder→reviewer)로 처리한다. PROGRESS.md에 기록:
        `## [시각] Group <id> 머지 후 통합검증 — FAIL · 실패한 verify: ...`
        같은 그룹에서 2회 연속 실패하면 루프를 멈추고 사용자에게 보고한다.
   **stage 경계 처리**: 한 stage의 모든 태스크가 완료되면 **stage-reviewer**
   (통합 검증)를 호출한다.
   - **입력 제한 [엄격]**: 브리핑에 담아 전달하는 것이 입력의 전부다 —
     ① stage 시작 커밋 sha(PROGRESS.md의 `Stage N 시작 — base=` 라인에서
     읽어 명시 — 통합 diff `<sha>..HEAD`의 기준점), ② PLAN.md에서 발췌한
     해당 stage 완료 조건, ③ PROGRESS.md에서 발췌한 **해당 stage 섹션만**,
     ④ 누적 NON-BLOCKING 목록. **PLAN.md·PROGRESS.md 전체 파일 주입 금지** —
     stage-reviewer가 두 파일을 직접 읽게 하지도 않는다.
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
     **[엄격] 해당 stage에 오케스트레이터 직접 처리(builder 미호출) 태스크가
     하나라도 있으면 위 생략 조건은 전부 무효다.** 그 태스크들은 독립 검증을
     한 번도 받지 않았으므로 stage-reviewer가 유일한 검증층이다 —
     태스크 2개 이하든 문서 전용이든 반드시 호출한다.
     판정은 기억이 아니라 로그로 한다: PROGRESS.md에서 해당 stage 블록의
     `builder=by=orchestrator`를 grep해 0건일 때만 생략이 성립한다.
     생략할 때는 그 사실과 근거를 stage 완료 보고에 한 줄로 남긴다
     (`Stage N 통합검증 생략 — 사유: [조건] · by=orchestrator 0건 확인`).
   - 결과를 PROGRESS.md에도 동일 구조화 형식으로 기록:
     `## [날짜시각] Stage N 통합검증 — [PASS|FAIL] · FINDINGS X건 · model=[opus|fable]`
     model=에는 **실제 투입된 모델**을 적는다. fable 승격 시 다음 줄에
     `- 승격사유: [해당 승격 조건]`을 추가한다.
   - **롤링 요약 (통합검증 기록 후 마지막 절차)**: PROGRESS.md가 stage 수에
     비례해 커지는 것을 막는다. 반드시 stage-reviewer 호출·기록이 **끝난 뒤**
     수행한다 (stage-reviewer 브리핑의 현 stage 발췌가 전문이어야 한다):
     1. 종료된 stage의 태스크 블록들, `Stage N 시작 — base=` 라인,
        `Stage N 통합검증` 블록 원문을 `PROGRESS.archive.md`(프로젝트 루트,
        없으면 생성)에 그대로 append — 요약으로 치환되는 모든 라인은
        반드시 archive에 원문이 먼저 남아야 한다.
     2. PROGRESS.md에서 해당 블록들을 요약 한 줄로 치환:
        `## Stage N 요약 — 태스크 X개 · FAIL Y건([유형 요약]) · 통합검증 [PASS|FAIL후PASS] · 결정: [주요 결정 or 없음]`
        (통합검증 라인은 요약에 흡수하고 삭제한다.)
     3. 단, **최근 5개 태스크 블록은 stage 소속과 무관하게 전문 유지**한다 —
        다음 태스크 브리핑의 NOTES/NON-BLOCKING 인계에 필요하다.
     4. `- 리뷰명령:` 줄은 요약 라인에 흡수하지 않는다 — archive에만 원문으로
        남긴다(계측용 원본이라 보존은 필요하되 stage-reviewer 입력을 키우면
        안 된다). 전문 유지 중인 최근 5개 블록에서는 그대로 둔다.
   - **RESUME 블록 갱신 (롤링 요약 후 [엄격])**: PROGRESS.md **최상단**의
     기존 `## RESUME` 블록을 교체한다(없으면 삽입):
     ```
     ## RESUME [시각]
     - 다음 태스크: N.M
     - 미해결 DECISIONS: [항목|없음]
     - 누적 NON-BLOCKING: [요약]
     - stage base sha: <sha> · 남은 워크트리: [경로들|없음]
     - 마지막 커밋 sha: <sha>
     ```
     목적: 새 세션이 PROGRESS 전체를 훑지 않고 이 블록만 읽고 재개하게 한다.
     기존 기록과 중복되더라도 한 곳에 모으는 것이 재개 비용을 낮춘다.
     루프 **중단 시에도** 같은 블록을 갱신한다(중단 조건 발동·pause 정지 포함).
     PreCompact 훅(`hooks/precompact-resume.sh`)이 컨텍스트 자동 압축 직전
     같은 형식의 블록을 기계적으로 갱신한다 — 오케스트레이터의 이 블록이
     1차 수단이고 훅은 압축으로 컨텍스트를 잃기 전의 안전망이다.
   - **세션 재시작 권고 (RESUME 갱신 후)**: 남은 stage가 있고 이번 세션의
     컨텍스트가 상당히 소모됐으면 stage 완료 보고에 한 줄을 포함한다:
     "stage N 완료. RESUME 블록 갱신됨. **`/clear` 후 '진행해'로 재개 권장** —
     진행 상태가 전부 파일(PLAN/PROGRESS/커밋)에 있어 재개는 무손실이고,
     긴 세션은 턴마다 누적 컨텍스트를 재처리해 토큰 소모가 커지며 규칙 준수도
     저하된다." 권고일 뿐 루프를 중단하지는 않는다.
5. **다음 태스크 브리핑은 오케스트레이터가 작성한다** — reviewer는 verdict만
   반환한다(NEXT TASK 없음 — 판정자와 계획자의 관심사 분리). PLAN.md의 다음
   미완료 태스크 정의에 builder NOTES·reviewer NON-BLOCKING 중 이번에 반영할
   것을 얹어 1의 브리핑 절차로 돌아간다.

## mode B 런처 — headless 트랙 병렬 [엄격]
PLAN.md 헤더가 `mode: B`이고 **사용자 승인이 기록된 경우에만** 진입한다.

### 실행 흐름
1. 메인 세션이 **계약 스테이지(Stage 0)를 직접 완료한다** — 계약은 직렬이다.
   계약 태스크도 정상 루프(builder→게이트→reviewer)를 거친다.
2. 트랙별 워크트리 생성:
   `git worktree add ../<repo>-track-<이름> -b plan/<기능명>-<트랙>` —
   리포 상위 폴더가 dev 루트여야 헌법이 상속된다(기존 워크트리 원칙과 동일).
   PLAN.md를 **트랙 스코프로 분할 배치**한다(각 워크트리에 그 트랙의 태스크만
   담긴 PLAN). 트랙별 **파일 소유권 목록(manifest)** 을 메인 PLAN.md에
   기록하고, 트랙은 자기 manifest 밖 파일을 수정할 수 없다 — 위반은 reviewer
   BLOCKING이고, 트랙 오케스트레이터의 `.dev-kit-scope`도 manifest 교집합으로
   한정된다.
3. 트랙마다 headless 세션을 백그라운드로 발사한다:
   `nohup claude -p "/dev-kit:execute-plan track <이름>" > .track-<이름>.log 2>&1 &`
   (작업 디렉토리 = 해당 트랙 워크트리)
4. 각 트랙은 태스크 경계마다 `.track-<이름>.status`에 3줄
   (현재 태스크 / 시도 횟수 / 마지막 커밋)을 갱신하고, 종료 시 결과
   (`COMPLETE|BLOCKED|DECISIONS|FAIL`)를 마지막 줄에 남긴다.
5. **메인 세션은 무한 폴링하지 않는다** — 발사 직후 상태 요약(트랙 목록·
   worktree 경로·status 파일 경로)을 출력하고 턴을 종료한다. 이후 사용자의
   "상태 확인해" 또는 재개 지시 시 status 파일들을 읽어 취합 보고한다.
   - 전 트랙 COMPLETE → 순차 머지 → 통합 테스트(전 트랙 verify를 메인
     트리에서 재실행 — B-5 게이트와 동일 원리) → stage-reviewer로 마감.
   - BLOCKED/DECISIONS가 있으면 취합해 사용자에게 묻는다. 해당 트랙의
     워크트리는 보존한다.

### 안전 제약 [엄격] — 런처보다 항상 우선
- headless 트랙 발사 명령에 **`--dangerously-skip-permissions`를 절대
  포함하지 않는다.** 이 옵션이 settings에 전역 설정된 흔적이 있으면
  발사를 거부하고 사용자에게 보고한다.
- headless는 확인 프롬프트에 답할 수 없다. 따라서 **파괴적 명령(§5)·verify
  allowlist 밖 verify를 만난 트랙은 실행을 시도하지 않고 BLOCKED로 기록한 뒤
  스스로 종료한다.** verify 선행 게이트의 allowlist·금지 패턴과 §5
  가드레일은 headless 트랙에도 **동일하게 적용된다** — 자동화 수준이
  올라가도 안전 확인은 한 단계도 생략하지 않는다.
- **push·배포·머지는 트랙 권한 밖이다.** 트랙의 종점은 "로컬 커밋 + status
  기록"까지이며, 머지는 메인 세션이 통합 스테이지에서만 수행한다.
- **발사 전 사전 점검**: ① `claude --version` 실행 가능, ② worktree 생성
  성공, ③ settings.json에 안전 명령(verify 테스트·루프 git 명령) allowlist
  존재. 하나라도 실패하면 **mode A로 강등해 진행하고 사유를 보고한다.**

### 기록
- 트랙별 PROGRESS.md는 **각 워크트리에** 남긴다 — 트랙이 소유·기록하며,
  태스크 루프의 기록 형식(구조화 라인·`- red:`·amend 한정 규칙 포함)을
  그대로 따른다.
- 통합 스테이지에서 메인 PROGRESS.md에 **트랙 요약**(태스크 수·재시도율·
  BLOCKED 수·소요)을 병합 기록한다. 트랙 로컬 PROGRESS 원문은 머지로
  히스토리에 남으므로 별도 전재하지 않는다.

## 경량화 규칙 (토큰 관리 — 헌법 §4 기본 검증 루프의 명시적 예외)
- 자명한 소형 태스크(설정 한 줄, 자명한 오타 수준)는 builder 없이 직접 처리해도 된다.
  단, 직접 처리한 태스크는 (a) PROGRESS.md에 `builder=by=orchestrator`로
  기록하고, (b) stage 경계의 stage-reviewer 브리핑에 **목록으로 명시**해서
  해당 diff의 태스크 레벨 검증을 받는다. **이때 stage-reviewer 생략 조건은
  전부 무효다** (위 stage 경계 처리의 생략 항목과 상호 참조 — 직접 처리는
  검증을 건너뛰는 권한이 아니라 검증을 stage 경계로 미루는 권한이다). 이 부류는 성격상 tier=light이므로 TDD(§3, standard
  한정) 대상이 아니다 — 판단이 들어가는 태스크는 직접 처리 대상이 아니다.
  **`risk: high` 태스크는 직접 처리 대상이 아니다** — 사전 승격의 목적이
  독립 opus 검증이므로 직접 처리는 그 목적을 통째로 우회한다.
- 연속된 소형 태스크 2~3개는 하나의 builder 브리핑으로 묶어도 된다.
  단, verify는 태스크별로 전부 실행한다.

## 중단 조건 (CLAUDE.md §4와 동일)
(a) 태스크 3연속 FAIL / (b) builder BLOCKED(`[전제 붕괴]` 한정 —
`[verify 미통과]`는 FAIL 카운트로 흡수) / (c) 전 태스크 완료
/ (d) 다음 태스크가 아키텍처 결정·파괴적 작업·요구사항 불명 포함
/ (e) 사용자 중단 지시 / (f) stage-reviewer 2회 연속 FAIL
/ (g) `.dev-kit-pause` 파일 존재
/ (h) 워크트리 그룹 머지 충돌, 또는 같은 그룹 머지 후 통합검증 2회 연속 FAIL
/ (i) **계약 변경 필요 (stop-the-world)** — mode A/B에서 계약 스테이지 산출물의
수정이 필요해지면 DECISIONS급으로 승격해 전 트랙을 태스크 경계에서 멈추고
사용자 확인 후 재개한다 (builder의 계약 파일 임의 수정은 reviewer BLOCKING).

중단·완료 시 보고: 완료 태스크 수, 남은 태스크, 발생 이슈, 리뷰어 NON-BLOCKING
누적 목록, 남아 있는 워크트리 경로(BLOCKED·통합 실패분). 보고 전에 PROGRESS.md의
RESUME 블록을 갱신한다 (stage 경계 처리의 RESUME 규칙과 동일 형식).

추가로 **검증 통계** 섹션을 포함한다 (PROGRESS.md **+ PROGRESS.archive.md**의
구조화 라인에서 집계한다 — 롤링 요약으로 압축된 stage의 원본 라인은 archive에 있다):
- 총 태스크 / 1회 통과 / 재시도 발생(비율%) / BLOCKED
- verify-gate FAIL 건수 (게이트가 리뷰 전에 차단한 라운드 수 = 절약된 리뷰 호출 수)
- tier별 분포 (light/standard 각 몇 건, light 승급 건수)
- risk별 분포 (normal/high 각 몇 건 — high는 전부 opus 사전 승격)
- FAIL 사유 상위 유형 (컨벤션 위반·기능 결함·verify 미충족·보안·기타)
- 리뷰 사후 승격 건수 / 오판율 (사후 승격 중 opus가 PASS로 뒤집은 비율 —
  높으면 sonnet이 과하게 깐깐, 승격이 0에 수렴하면 느슨할 가능성)
