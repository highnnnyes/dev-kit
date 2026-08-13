# CHANGELOG

버전 bump마다 항목을 추가한다. 형식: `## vX.Y.Z — 날짜` + 변경 요약 불릿.
기기 간 `/plugin update dev-kit` 후 이 파일로 변경분을 확인한다.

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
