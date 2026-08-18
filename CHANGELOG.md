# CHANGELOG

버전 bump마다 항목을 추가한다. 형식: `## vX.Y.Z — 날짜` + 변경 요약 불릿.
기기 간 `/plugin update dev-kit` 후 이 파일로 변경분을 확인한다.

## v1.11.0 — 2026-08-18
PATCH 3 — 실측 지표 + 진입점. 원칙: **지표는 PROGRESS.md에 이미 남는
데이터에서만 계산한다** (계측용 새 기록 의무는 `- 시작:` 1줄까지만).
목적: 주장(재시도율 건강 범위·단축 폭 추정)을 실측값으로 교체할 산출 장치와
30초 진입점.

- **`/dev-kit:metrics` 신설** (commands/metrics.md): PROGRESS.md(+archive,
  mode B는 `PROGRESS.<트랙>.md`)를 파싱해 태스크 수/완료·중단, 재시도율
  (FAIL÷태스크, verify-gate/리뷰 FAIL/red 미확인 분해 + 건강 범위 10~30%
  판정 1줄), 태스크 소요(평균·중앙값·최장)·총 월클럭(병렬 구간은 시작·종료
  구간 **합집합** — 중복 합산 금지), 병렬 효율(소요 합계÷월클럭, 상한 3
  또는 트랙 수 대비 %), red: CONFIRMED 비율을 표 1개+코멘트 3줄로 출력.
  인자 2개면 비교 모드(단축률) — 순차 vs mode A 용도. 오케스트레이터 직접
  절차(서브에이전트 금지). **[엄격] 파싱 실패는 추정으로 메우지 않고
  `n/a (사유)` 표기** — 지표 신뢰성이 존재 이유.
- **타임스탬프 정합** (execute-plan·audit C): PROGRESS 태스크 블록에
  `- 시작: [날짜시각]` 1줄 신설(첫 디스패치 시점 — 헤더 시각이 종료 시점,
  소요 계산 쌍). mode B 트랙 PROGRESS 파일명을 `PROGRESS.<트랙>.md`로
  분리 — 머지 시 메인 PROGRESS.md와 충돌하지 않고 태스크별 타임스탬프
  원문이 메인 히스토리에 보존된다(기존 동명 파일이면 머지 충돌·원문 소실).
  audit C에 타임스탬프 정합 검사 신설(새 기록 의무 1줄 초과 금지 포함).
- **README 진입점 재구성**: 최상단 3줄 요약(무엇/무엇이 다른가/누구에게) →
  데모 자리(docs/demo.gif 주석 태그 — 녹화 전 가짜 파일 생성 금지 [엄격],
  녹화 절차 `asciinema rec → agg` 주석) → "Measured on real runs" 스켈레톤
  (`<!-- /dev-kit:metrics 출력으로 교체 -->` — 숫자 지어내기 금지 [엄격]) →
  기존 본문. 추정 서술("수 배 소모 가능")에 "추정 — 실측으로 교체 예정"
  표기. 사용법에 metrics 항목 + 측정 프로토콜(순차/mode A 각 1회 완주 →
  각각 metrics → 비교 출력 첨부).

## v1.10.0 — 2026-08-18
PATCH 2 — 계약 우선(Contract-First) 병렬 실행 구조. 원칙: **병렬화는 계약
파일이 먼저 존재할 때만 허용하고, 자동화 수준이 올라가도 안전 확인은 한
단계도 생략하지 않는다.** 새 에이전트 없음, 별도 커밋(롤백 단위 분리).

- **계약 스테이지** (write-plan [엄격]): role 2종+ 계획은 Stage 0 강제 —
  경계 파일(타입·API 시그니처·스키마) + mock 계약 테스트. 이후 태스크는
  구현이 아니라 계약에만 의존(충족 시 [P] 적극 부여). tier=standard 고정,
  대형/고위험이면 grill 심문에 계약 포함. **계약 변경은 stop-the-world** —
  DECISIONS급 승격·전 트랙 정지·사용자 확인 (중단 조건 (i) 신설, 헌법 §4
  동기). builder의 계약 파일 임의 수정 = reviewer BLOCKING + scope 훅 차단.
- **사이즈 라우팅 mode: S|A|B** (write-plan·헌법 §4): 계획 생성 직후 판정해
  PLAN.md 헤더 기록. S(8개 미만·본질 직렬)=현행 순차, A(8+·role 2종+)=계약
  스테이지+[P] 병렬, B(15+·트랙 비중첩·편차 작음)=자동 진입 금지·분할안
  출력 후 승인 대기(승인 시 헤더에 `승인:` 기록 — 런처 진입 조건). 애매하면
  보수적 강등(S>A>B), 기준값 8/15 [유연], 오버라이드("B로 올려"/"순차로 해")
  헤더 기록, 헤더 없으면 S(하위 호환).
- **mode A 병렬 강화** (execute-plan): [P] 리뷰 병렬 디스패치(읽기 전용 +
  워크트리별 diff 독립 — 기존 "순차 리뷰" 교체), 인터리빙 스케줄링(그룹
  대기 대신 의존 충족 태스크 풀로 슬롯 상한 3 상시 충전, 메인 트리 직렬
  태스크는 동시 1개, 그룹 머지·B-5 게이트는 유지). verify 게이트·리뷰
  밀도는 병렬에서도 태스크별 동일 [엄격].
- **mode B 런처 — headless 트랙 병렬** (execute-plan [엄격]): 계약 스테이지
  직렬 완료 → 트랙별 `../<repo>-track-<이름>` 워크트리 + PLAN 분할 배치 +
  manifest(밖 수정 = BLOCKING, scope 훅 교집합) → `nohup claude -p
  "/dev-kit:execute-plan track <이름>"` 백그라운드 발사 → 트랙은 태스크
  경계마다 `.track-<이름>.status`(3줄+결과) 갱신. 메인은 폴링하지 않음 —
  발사 후 턴 종료, 지시 시 status 취합. 전 트랙 COMPLETE 시 머지→통합
  테스트→stage-reviewer. **안전 제약이 런처보다 상위**:
  `--dangerously-skip-permissions` 절대 금지(전역 설정 흔적 시 발사 거부),
  headless는 파괴적 명령·allowlist 밖 verify를 만나면 실행 시도 없이
  BLOCKED 자기 종료, push·배포·머지는 트랙 권한 밖, 발사 전 점검 3종
  실패 시 mode A 강등.
- **PROGRESS 소유권 스코프 개정** (v1.9.1 규칙 선행 조정): mode S/A [P]
  워크트리 태스크는 기존 유지(메인 트리 소유·머지 후 기록·amend 대상 아님),
  mode B 트랙은 트랙 로컬 PROGRESS.md 소유·기록 + amend 한정 규칙 동일
  적용, 메인 PROGRESS에는 통합 스테이지에서 트랙 요약만 병합.
- README: 다이어그램 mode 분기·계약 스테이지, 오버라이드 예시, mode B 사전
  요구사항(worktree·settings allowlist·Max 플랜 권장)·토큰 경고, [엄격]/
  [유연] 목록 갱신. audit C에 계약 5종 추가(mode 헤더 4자·계약 스테이지
  3자·런처 status·소유권 스코프·amend 구분).

## v1.9.1 — 2026-08-18
v1.9.0 게이트 봉합 2건 [엄격].

- **`[green]` amend 파일 한정** (execute-plan): 리뷰 PASS 후 amend로 수정
  가능한 파일은 PLAN.md·PROGRESS.md 둘뿐 — amend 직전 스테이징 diff
  (`git diff --cached --name-only`)에 그 외 파일이 있으면 amend 없이 중단·
  보고. 근거: 리뷰어가 판정한 diff와 최종 커밋의 동일성 보장. 리뷰 FAIL 후
  수정분 amend는 재검증 전이라 대상 아님(재리뷰가 다시 판정). 워크트리
  병렬 태스크는 기록이 메인 트리 소유라 대상 아님(머지 후 메인 트리 기록).
- **절차형 verify 예외를 열거형으로 전환** (execute-plan·write-plan):
  허용 목록은 docs "drift 스캔 통과"·harden "증거 칸 충족" **2종뿐**.
  목록 밖 비-셸 verify는 절차형으로 간주하지 않고 게이트 정지 대상 —
  "절차형" 라벨링을 통한 게이트 우회 차단. 목록 추가는 프로젝트 CLAUDE.md
  오버라이드 불가, 헌법 개정(dev-kit 파일 수정)으로만 가능.
- audit C: 절차형 2종 열거 양자 일치·amend 한정 규칙 존재 검사 추가.

## v1.9.0 — 2026-08-18
검증 신뢰성과 토큰 효율 동시 개선 — 원칙: **리뷰어(opus) 호출 횟수를 줄이는
방향으로만 신뢰성을 높인다.** 새 에이전트·스킬·파일 없이 기존 5파일 계약 개편.

- **verify 선행 게이트** (execute-plan [엄격]): builder 완료 보고 후 reviewer
  호출 **전에** 오케스트레이터가 해당 태스크 verify를 직접 1회 실행. 실패 →
  reviewer 미호출, 실패 출력 마지막 20줄로 재시도 브리핑, 3회 FAIL 카운트
  산입 + PROGRESS `FAIL(verify-gate)` 유형. 성공 → `verify: PASS
  (orchestrator-run)` 1줄을 리뷰 브리핑에 포함. builder 자기 보고는 참고
  정보 — 진실의 원천은 오케스트레이터 독립 실행 (자기 보고 조작·환각 원천
  차단 + 실패 라운드당 리뷰 1회 절약).
  **안전 제약이 게이트보다 상위 [엄격]**: 자동 실행은 패키지/빌드 스크립트
  형태(npm run/pnpm/yarn/make/pytest/go test/cargo test/tsc --noEmit +
  프로젝트 CLAUDE.md allowlist)만, `rm`/`drop`/`truncate`/`delete`/`reset`/
  `migrate`/`push`/`deploy`/`curl`/`wget`·파이프·연쇄·리다이렉션 포함 시
  allowlist 무관 금지, 헌법 §5·permission rules 그대로 적용("게이트니까
  확인 생략" 해석 차단). write-plan에 "verify는 부수효과 없는 명령만" 규칙
  신설 — DB 테스트는 테스트 전용 리소스 확인 불가 시 DECISIONS로 승격,
  개발 DB·공유 리소스 verify 작성 금지.
- **TDD 증거를 git 히스토리로 이전** (builder·reviewer·execute-plan [엄격]):
  tier=standard 코드 태스크를 red/green 2단 디스패치로 분리 —
  `[plan N.M][red] 테스트 추가` 커밋 직후 오케스트레이터가 실패를 직접
  확인(`red: CONFIRMED` 기록, 처음부터 green이면 재작성 지시) →
  `[plan N.M][green] 구현` 커밋은 verify 게이트가 독립 확인. reviewer의
  red→green 기록 감사 삭제, "신규 테스트 존재 + assert 실체성"만 검사 —
  기록 조작 가능성 제거(커밋·실행 결과는 위조 불가) + opus 입출력 절약.
- **NEXT TASK를 reviewer에서 오케스트레이터로 이관** (reviewer·execute-plan):
  reviewer 출력을 VERDICT/BLOCKING/NON-BLOCKING(최대 5) + 추적표·VERIFIED로
  고정, 다음 태스크 브리핑 생성 책임은 execute-plan 5로 완전 이관.
  [P] 그룹 "마지막 리뷰만 NEXT TASK" 특례 삭제. 판정자·계획자 관심사 분리
  + 태스크 수만큼 곱해지는 출력 토큰 절감.
- **리뷰 입력 다이어트** (execute-plan·stage-reviewer): reviewer 입력을
  4종으로 제한(태스크 정의 원문·diff·오케스트레이터 verify 결과 1줄·프로젝트
  CLAUDE.md) — PROGRESS·설계 문서·이전 태스크 내역 주입 금지. stage-reviewer
  입력은 브리핑 발췌만(base sha·stage 완료 조건·PROGRESS 해당 stage 섹션·
  누적 NON-BLOCKING) — PLAN/PROGRESS 전체 주입·직접 읽기 금지.
- **조건부 승인 게이트** (헌법 §4 라우팅 3번 [유연 기준값]): DECISIONS가
  없어도 태스크 8개↑ 또는 stage 3개↑ / 신규 파일 5개↑ / 스키마 변경·외부
  API·의존성 추가 포함이면 계획 출력 후 1회 확인 대기. 소형 계획은 기존대로
  즉시 실행. 근거: 대기는 토큰 무소모, 어긋난 계획 되돌리기(builder+reviewer
  재실행)가 게이트 1회보다 항상 비쌈. 기준값은 프로젝트 CLAUDE.md 오버라이드.
- README: 아키텍처 다이어그램에 게이트·2단 디스패치 반영, 계측에
  `FAIL(verify-gate)`·`red: CONFIRMED` grep 추가, 모델 티어링 아래 게이트
  우선 원칙, verify 이식성 → 강제 조건으로 격상. audit C에 계약 4종 추가
  (TDD 2단·verdict-only·입력 제한·양 게이트 다자 일치).

## v1.8.2 — 2026-08-15
프롬프트 캐시 적중률 보존. 캐싱은 Claude Code가 자동 적용하지만 적중은
접두사(에이전트 정의 + 도구 정의 + CLAUDE.md) 동일성에 달려 있으므로 루프
설계로 관리한다 — 깨지면 서브에이전트 호출마다 고정 오버헤드를 정가로 재지불
(2026-03 캐싱 장애 당시 소모 10~20배 전례). 사용자 지정 버전은 1.8.1이었으나
동번호가 이미 배포돼 있어(1.8.0→1.8.1 때와 동일 상황) 1.8.2로 진행.

- **실행 중 CLAUDE.md 수정 금지** (execute-plan 신규 섹션 [엄격]): 루프 중
  헌법·프로젝트 CLAUDE.md 수정 금지 — 캐시 접두사라 중간 수정 시 남은 태스크
  전부 캐시 무효화. 수정 태스크는 stage 말미로 미루고, 수정 후 새 세션 권고
  (RESUME 블록 갱신 포함).
- **CLAUDE.md 수정 태스크 stage 말미 배치** (write-plan 분해 원칙 8 신설
  [엄격], 기존 ROLES는 9로): docs·harden 스킬이 심는 태스크에도 적용 —
  두 스킬의 루프 통합 절에 동일 제약 명시.
- **같은 tier·risk 태스크 인접 정렬** (write-plan 분해 원칙 4 확장): 의존
  순서 최우선, 동률일 때만 적용 — 모델이 바뀌면 캐시가 갈리므로 같은 모델
  태스크 연속 배치로 적중률을 높인다.
- **대기 시간 최소화** (README 토큰 관리 "프롬프트 캐시 적중률 보존" 신설):
  승인 대기로 루프가 멈추면 캐시 TTL 만료 — verify 테스트·빌드 명령과 루프
  git 명령의 permissions allow 등록은 비용 문제이기도 하다(파괴적 명령은
  v1.8 훅이 별도 차단하므로 allow 확대와 안전이 상충하지 않음).
- audit C에 계약 1종 추가: stage 말미 배치 규칙의 write-plan·execute-plan·
  docs·harden 4자 일치.

## v1.8.1 — 2026-08-15
v1.8 2차분 — 격리·차단·체크포인트. 원칙: **규칙이 아니라 기계적 장치로 막는다**
(세 실사고 — DB 전소·병렬 산출물 checkout 파괴·리뷰어 읽기 전용 위반 — 전부
마크다운 규칙이 못 막았다). 1차분(1.8.0: 데이터 파괴 훅·harden·DESTRUCTIVE 행)이
이미 배포돼 있어 버전만 1.8.1로 진행한다.

- **훅 되돌리기 범주 신설** (`block-destructive.sh`): "미커밋 작업을 없애거나
  워킹트리를 되돌리는 모든 명령" 범주 — `git checkout <경로>`/`git restore`/
  `git clean`/`git stash`(list·show 제외)/`git rm`/`git branch -D`(-d 허용)/
  `git reflog expire`를 전면 deny(확인 아님 — 복구는 사용자 몫). 오탐 방지:
  `git checkout -b`·브랜치 전환은 허용 — 인자 파일 실존 검사로 경로 checkout만
  판별(워크트리가 브랜치 조작에 의존하므로 필수). 실측 49케이스 전부 통과.
- **스코프 밖 쓰기 차단** (matcher Bash → Bash|Edit|Write): 오케스트레이터가
  디스패치 직전 `.dev-kit-scope`에 대상 파일 목록을 쓰고, 훅이 목록 밖
  Edit/Write를 deny. 파일 없으면 검사 생략(수동 세션). 한계: 동시 디스패치
  태스크 간 교차는 못 막음(둘 다 목록에 있음) — 그 층은 워크트리가 담당.
- **워크트리 격리** (execute-plan·write-plan·헌법): [P] 그룹을 태스크별
  `<dev 루트>/.worktrees/<project>/<task-id>` + `wt/<task-id>` 브랜치에서 물리
  격리 실행. 프로젝트 CLAUDE.md `worktree: shared-env|isolated-env|off` 선언제
  (기본 off — [P] 순차 강등). PLAN/PROGRESS는 메인 트리 소유(워크트리 접근
  금지 → 머지 무충돌 실측). reviewer는 워크트리 안 `git diff HEAD~1` — 스코프
  자동 보장. **머지 후 통합 검증 게이트**: 그룹 머지 직후 전 태스크 verify를
  메인 트리에서 재실행(오케스트레이터 직접, 모델 호출 없음. 그룹 크기 1 생략,
  2연속 실패 시 중단). write-plan [P] 금지 조건 신설: 의존성 변경·네임스페이스
  공유(마이그레이션 버전·라우트·설정 키·픽스처·DI 등록명). 정리 실패 내성
  (경고 후 진행 + 시작 시 prune) 실측 16케이스 전부 통과.
- **세션 체크포인트**: stage 완료·루프 중단 시 PROGRESS.md 최상단 RESUME 블록
  (다음 태스크·미결 DECISIONS·누적 NON-BLOCKING·base sha·워크트리·마지막 커밋).
  **PreCompact 훅 신규**(`precompact-resume.sh`): 자동 압축 직전 같은 블록을
  기계적으로 flush(PreCompact는 컨텍스트 주입 불가·부수 효과만 가능 — 공식
  문서 확인). 재개 절차가 이 블록을 우선 읽음. README에 `/clear` > `/compact`
  근거 명시.
- **헌법 §5 재구성**: 파괴 명령을 데이터 파괴(확인)·되돌리기(전면 금지) 2범주로
  분리, 초기화 원칙("데이터를 지우는 방식으로 환경을 초기화하지 마라") 추가,
  역할 분담 명시(규칙=관측·설명, 훅=강제, 권한=최종 보증). §4에 워크트리 요약.
- audit C 계약 8종 추가(훅 2종 등록·scope 생산/소비·worktree 라우팅·B-5 게이트·
  base sha 3자·RESUME 2원·harden 라우팅).

## v1.8.0 — 2026-08-14
파괴 방어를 3층으로 구성: 지시문(관측) → 훅(차단) → 환경 권한(보증).
E-1(파괴적 명령 준수가 산출물에 무흔적)의 해소를 겸한다.

- **PreToolUse 훅 신규** (`hooks/hooks.json` + `hooks/block-destructive.sh`):
  matcher=Bash. DROP SCHEMA/DATABASE/TABLE·TRUNCATE·`delete … where 1=1`·
  dropdb·pg_restore·`docker compose down -v`·`docker volume rm`·`rm -rf`·
  `git reset --hard`·`git push --force`를 `permissionDecision: deny`로 차단.
  프로젝트 루트 `.dev-kit-allow-destructive`에 패턴 ID를 적으면 예외
  (git 추적 필수, 적용 시 stderr에 흔적). 파서(jq→python3) 부재·깨진 입력·
  예외 상황은 전부 exit 0(fail open)이라 훅이 루프를 죽이지 않는다.
  스크래치 실측: 차단 15/15, 통과 7/7, 예외 파일·주석 처리·fail open 확인.
- **skills/harden 신규** [엄격]: L1 DB 권한 → L4 백업 → L5 dev/prod 격리
  8개 항목 점검표. **각 항목은 증거 칸을 채워야 완료**(증거 없는 "설정함"은
  미완료). 결과는 HARDENING.md. write-plan은 DB가 있는데 HARDENING.md가
  없으면 Stage 1에 harden 태스크(risk: high)를 심는다. 헌법 §4 자동 라우팅에
  6번 항목으로 추가(기존 "사소한 작업"은 7번으로 이동).
- **builder/builder-light 출력에 DESTRUCTIVE 행**: 실행한 파괴적·비가역
  명령 전부 + 사용자 확인 여부, 없으면 "없음" 명시(빈칸이면 출력 미충족).
  reviewer가 검사 항목으로 감사(확인 없이 실행 → BLOCKING, 유형 `보안`),
  execute-plan이 PROGRESS.md `- 파괴적명령:`으로 전재.

## v1.7.0 — 2026-08-14
v1.6 산출물 제약 원칙의 후속 적용 4종. 계기: 실사용 로그 160태스크에서
리뷰어가 무엇으로 diff를 봤는지 판별 불가(`git diff`/`git status` 언급 5건)
— 규율은 있는데 관측 칸이 없어 준수 여부를 실측할 수 없는 상태였다.

- **리뷰 실행 명령 전량 기록** (reviewer·stage-reviewer VERIFIED,
  execute-plan PROGRESS 기록): 실행한 Bash 명령을 원문 그대로 누락 없이
  나열한다(축약 금지, 누락 시 VERIFIED 미충족). 스코프 준수와 읽기 전용
  준수가 같은 목록으로 동시 관측된다. PROGRESS.md에 `- 리뷰명령:` 줄로
  요약 없이 전재.
- **신규 파일 스코프 결함 수정** (execute-plan): `git diff`가 untracked
  신규 파일을 누락하는 문제(실측 재현) — reviewer 호출 직전 CHANGED 목록
  한정 `git add -N`으로 노출시킨다. 실측: 부분 스테이징 커밋에 딸려 들어가지
  않음, `git add -N .`은 병렬 그룹 오염으로 금지, reviewer 직접 실행 금지
  (읽기 전용 위반). reviewer.md에도 신규 파일 미노출 시 Read 확인 규칙 추가.
- **검증 우회 차단** (execute-plan): 오케스트레이터 직접 처리 태스크가 있는
  stage는 stage-reviewer 생략 조건이 **전부 무효** [엄격]. 판정은 기억이
  아니라 로그로 — PROGRESS.md에 `builder=by=orchestrator`를 남기고
  grep 0건일 때만 생략 성립. 생략 시 근거를 완료 보고에 명시.
- **태스크 기준 단위 정리** (write-plan·헌법 §4·README·plugin.json):
  1차 기준을 "verify 하나로 통과/실패가 갈리는 단위 = 테스트 1~2개 + 그
  구현"으로 올리고 시간(5~10분)은 괄호 참고치로 강등. 근거: 에이전트는
  소요 시간을 추정하지 못하지만 verify 하나는 산출물로 확인 가능하다.

## v1.6.0 — 2026-08-13
리뷰어 감도 실험(같은 모델, 지시문만 교체, 4라운드) 결과 반영. 핵심 발견:
서술형 지침("무엇을 확인하라")은 반복적으로 무시됐고, 산출물 제약("이 칸을
이런 증거로 채워라, 못 채우면 실패")은 지켜졌다 — 결함 검출 2/4 → 4/4.

- **요구사항 추적표** (reviewer 출력, VERIFIED 앞): 브리핑의 요구사항을 전부
  행으로 나열하고 각 행에 충족 증거를 적는다. 수치·경계·길이·개수 조건은
  코드 읽기를 증거로 삼을 수 없고 python -c 등의 실행 명령+출력을 붙여야
  한다. red→green 기록 감사는 전용 행. 빈칸 행이 하나라도 있으면 BLOCKING,
  BLOCKING을 찾아도 표는 끝까지 완성. 기존 서술형 체크리스트의 경계값 확인·
  TDD 기록 감사 항목은 표 참조로 정리(중복 제거).
- **읽기 전용에 Bash 우회 금지 명시** (reviewer, stage-reviewer): Write/Edit
  부재가 읽기 전용을 보장하지 않는다 — sed -i·리다이렉션·스크립트 실행도
  금지. 뮤테이션 검증은 python -c 직접 호출 또는 리포 사본/git stash에서.
- **리뷰 사전 승격 (risk 태그)**: write-plan이 요구사항에 수치·경계·개수
  조건, 보안, 데이터 변형/삭제, 동시성이 포함된 태스크에 `risk: high`를
  달고(기본 normal), execute-plan이 그 태그로 **FAIL 여부와 무관하게 처음부터
  opus 리뷰**로 라우팅한다. 근거: 사후 승격만으로는 약한 리뷰어가 놓쳐서
  PASS시킨 결함이 승격을 트리거하지 못한다. 사전 승격은 태스크 속성이라
  모든 라운드 유지, PROGRESS.md에 `reviewer=opus(사전승격)`·`risk=`로 기록
  (오판율 통계는 사후 승격만 집계).
- **헌법 §1에 "규율은 산출물로 강제한다" [엄격] 추가**: 반드시 지켜져야 하는
  검사는 지시문이 아니라 출력 필드로 표현한다. _template의 스킬 TDD 절에
  연결(green이 안 나오면 산출물 제약으로 전환).

## v1.5.2 — 2026-08-08
fable 사용량 절감 3종. 실측 배경: 4세션×2h 실행 루프(fable 메인)에 fable
주간 한도 10%+ 소진 — 주범은 메인 세션 모델. 예상 효과: fable 미터 ~90%
절감(설계·위험 stage 승격만 잔존), 총 토큰 ~10~20% 절감. 품질 영향:
코드 산출물 0(서브에이전트 모델 무변경), 오케스트레이션은 재시도율로 관측.

- **모델 가드** (execute-plan 사전 체크 0번, 헌법 §4): 루프 시작 시 메인
  모델이 fable이면 시작하지 않고 `/model opus` 전환 권고 — "fable로 진행해"
  로 우회 가능. 세션당 1회, 태스크 경계 재확인 없음.
- **role 페르소나 사전 생성** (write-plan ↔ execute-plan 계약): PLAN.md에
  `## ROLES` 블록을 작성 시 1회 생성, 브리핑은 복사만. 블록 없는 구버전
  PLAN.md는 기존대로 즉석 작성 (하위 호환).
- **stage 경계 세션 재시작 권고** (execute-plan, README): 롤링 요약 후
  남은 stage가 있으면 새 세션 재개 권장 한 줄 — 권고only, 루프 중단 없음.
- README 플랜/토큰 한도 절에 다중 세션 운용 지침 추가, plugin.json
  description "2-5min"→"5-10min" (v1.5.1 감사 WARNING 해소).

## v1.5.1 — 2026-08-07
리뷰 티어링 스펙 구멍 봉합 — 실측(Stage 4)에서 실행 세션이 수정 후
재검증을 opus로 이어 보내는 절차 이탈 발생. 원인은 "opus verdict가
최종" 문구가 opus 유지로 읽힐 여지.

- **승격 라운드 독립 명시** (execute-plan, 헌법 §4, README): 수정 후
  재검증은 다시 sonnet 기본 호출부터 시작 — 직전 라운드가 opus였다는
  이유로 opus를 이어 쓰지 않는다. 승격 메커니즘·오판율 기록은 무변경.

## v1.5.0 — 2026-08-07
비용 구조 개선 3종. 절대 조건: 재시도율 5% 유지 — 적용 후 1~2개 stage
실측에서 재시도율 급락(0~2%) 또는 stage-reviewer FINDINGS 증가 시
리뷰 티어링을 롤백한다 (README 재시도율 해석 기준 참조).

- **PROGRESS.md 롤링 요약** (execute-plan, stage-reviewer, README):
  stage 종료(통합검증 기록 후) 시 해당 stage 블록을 요약 한 줄로 압축,
  원문은 PROGRESS.archive.md에 선기록. 최근 5개 태스크 블록은 전문 유지.
  stage-reviewer는 PROGRESS.md만 읽음 — 입력이 stage 수와 무관하게 상수.
  검증 통계는 PROGRESS.md + archive 합산.
- **reviewer 2단 티어링** (reviewer, execute-plan, 헌법 §4, README):
  기본 sonnet, FAIL 시에만 opus 재검증 — opus verdict 최종. FAIL 카운트는
  최종 verdict 기준. reviewer=[sonnet|sonnet→opus] + 승격리뷰 줄로 오판율
  추적. 헌법 기본 검증 루프(단발 경로)에도 동일 승격 규칙 동기화.
  stage-reviewer는 opus(조건부 fable) 유지.
- **태스크 분해 단위 5~10분** (write-plan, 헌법 §4, README): 상한
  "신규/확장 테스트 1~2개 + 구현" 명시, [P그룹]·TDD 규칙 무변경, 예시 갱신.
- 롤백: 변경별 커밋 분리 — 티어링 롤백은 reviewer frontmatter `opus` 복원
  + execute-plan 승격 절 + 헌법 §4 승격 문구 제거 (또는 해당 커밋 2건 revert).

## v1.4.1 — 2026-08-07
외부 리뷰(전 파일 검토) 검증 후 유효 결함 반영.

- **병렬 그룹 스코프 격리** (execute-plan, reviewer): 병렬 [P] 그룹 완료 후
  리뷰·커밋 시 각 builder의 CHANGED 파일 목록으로 `git diff -- <파일들>`
  스코프 한정 + `git add` 부분 스테이징. `git commit -a` 금지. FAIL 태스크
  변경은 워킹트리에 남기고 PASS만 커밋.
- **검증 우회 경로 차단** (execute-plan, stage-reviewer): 오케스트레이터가
  직접 처리한 태스크가 있으면 stage-reviewer 생략 불가. 직접 처리 태스크는
  브리핑에 목록으로 명시하고, stage-reviewer의 "개별 diff 재리뷰 금지"의
  예외로 태스크 레벨 검증.
- **stage base sha 기록** (execute-plan, stage-reviewer): stage 첫 태스크
  착수 전 PROGRESS.md에 `## [날짜시각] Stage N 시작 — base=<sha>` append.
  stage-reviewer 스코프는 이 sha를 브리핑으로 전달받는다.
- **builder BLOCKED 사유 태그** (builder, builder-light, execute-plan):
  BLOCKED 사유 첫 줄에 `[전제 붕괴]`/`[verify 미통과]`(light는 `[판단 필요]`
  포함) 태그. 오케스트레이터는 `[전제 붕괴]`만 루프 중단, `[verify 미통과]`는
  정상 FAIL 카운트로 흡수 — verify 실패가 자율 루프 전체를 멈추지 않게.
  헌법(§4)·execute-plan의 중단 조건 (b)도 `[전제 붕괴]` 한정으로 동기화.
- **light 승급 시 tier 재판정** (execute-plan, builder): `[판단 필요]` 승급은
  오분류이므로 PLAN.md tier를 standard로 재기입하고 TDD 적용. `[verify
  미통과]` 승급은 light 유지. light 승급의 TDD 영구 면제 구멍 제거.
- **reviewer NEXT TASK 어휘 수정** (reviewer): "단계(stage)" 어휘 오염 제거 —
  NEXT TASK는 태스크(N.M) 단위로 통일.
- **audit E절 확장** (audit): model 필드 유효성 + 티어링 실측 절차 추가.
- **marketplace.json description 갱신**: v1.2 시절 요약 → 현재 기능 반영
  (tier 라우팅, TDD, stage-reviewer, debugging/audit).
- **CHANGELOG.md 신설**: 이 파일. 이후 버전 bump 시 갱신 [엄격].
