# CHANGELOG

버전 bump마다 항목을 추가한다. 형식: `## vX.Y.Z — 날짜` + 변경 요약 불릿.
기기 간 `/plugin update dev-kit` 후 이 파일로 변경분을 확인한다.

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
