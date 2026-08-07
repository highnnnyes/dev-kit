# CHANGELOG

버전 bump마다 항목을 추가한다. 형식: `## vX.Y.Z — 날짜` + 변경 요약 불릿.
기기 간 `/plugin update dev-kit` 후 이 파일로 변경분을 확인한다.

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
