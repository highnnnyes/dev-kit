# dev-kit — 프로젝트 CLAUDE.md

Claude Code 플러그인 리포. 순수 마크다운 — 빌드·테스트·런타임 의존성 없음.
방법론 설명은 여기 반복하지 않는다 → README.md 참조.

## 파일 라우팅
- 헌법 템플릿 (자동 라우팅·검증 루프·가드레일) → `CLAUDE.md.template`
- 사용법·설치·튜닝·환경별 함정 → `README.md`
- 서브에이전트 (builder / builder-light / reviewer / stage-reviewer) → `agents/`
- 커맨드 (write-plan / execute-plan) → `commands/`
- 스킬 (brainstorming / grill / docs / debugging / audit / _template) → `skills/`
- 버전별 변경 이력 → `CHANGELOG.md`

## 수정 규칙
- **[엄격]** plugin.json version을 올리기 전에 audit 스킬을 반드시 실행한다.
  BLOCKING이 있으면 해결 전 push 금지. WARNING은 사용자 판단.
  감사 결과 요약은 커밋 메시지 본문에 한 줄로 남긴다.
- 수정 후 `.claude-plugin/plugin.json` version 올리고 push → 각 기기에서
  `/plugin marketplace update dev-kit` + `/plugin update dev-kit`.
- **[엄격]** version bump 시 `CHANGELOG.md`에 해당 버전 항목을 추가한다.
- `CLAUDE.md.template`은 `~/dev/CLAUDE.md`로 **심볼릭 링크** 배포 —
  git pull만으로 즉시 반영된다 (plugin update 불필요).
- 계약 필드명(STATUS, VERDICT, NEXT TASK, STAGE VERDICT, tier 등)을 바꾸면
  생산·소비하는 파일을 반드시 동시 수정한다
  (builder/builder-light ↔ execute-plan ↔ reviewer/stage-reviewer ↔ write-plan).

## 컨벤션
- 문서는 한국어로 작성한다.
