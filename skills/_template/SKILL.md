---
name: _template
description: 새 도메인 지식 스킬을 만들 때 복사하는 템플릿. 실제 스킬이 아니므로 로드하지 말 것.
---

# [도메인명] 스킬 작성 가이드

이 폴더를 복사해서 새 도메인 스킬을 만든다:
`skills/_template/` → `skills/design/`, `skills/youtube-automation/`, `skills/blog-automation/` 등

## 구조 원칙 — 목차와 본문 분리 (progressive disclosure)

```
skills/design/
├── SKILL.md          # 목차 + 핵심 원칙만 (짧게 — 이것만 우선 로드됨)
└── references/       # 상세 본문 (SKILL.md가 지시할 때만 읽힘)
    ├── color-system.md
    ├── typography.md
    └── layout-patterns.md
```

- **SKILL.md는 200줄 이하.** frontmatter의 description이 트리거 조건을
  결정하므로 "언제 이 스킬을 써야 하는지"를 구체적으로 쓴다.
  예: "UI 디자인, 랜딩페이지, 대시보드 스타일링 작업 시 사용"
- **본문은 references/에.** SKILL.md에는 "색 체계가 필요하면
  references/color-system.md를 읽어라"처럼 라우팅만 적는다.
  이러면 관련 작업일 때만, 필요한 파일만 컨텍스트에 로드된다.
- 매 세션 로드돼야 하는 규칙(항상 지켜야 할 원칙)은 스킬이 아니라
  CLAUDE.md에 넣는다. 스킬은 "필요할 때 꺼내 쓰는 지식"이다.

## SKILL.md 골격 (복사용)

```markdown
---
name: design
description: UI/UX 디자인 작업(랜딩페이지, 대시보드, 컴포넌트 스타일링) 시 사용. 색·타이포·레이아웃 기준과 참조 문서 라우팅.
---

# Design

## 핵심 원칙 (항상 적용)
- [3~7개 불변 원칙]

## 참조 라우팅 (필요할 때만 읽기)
- 색 체계 → references/color-system.md
- 타이포그래피 → references/typography.md
- 레이아웃 패턴 → references/layout-patterns.md

## 작업 절차
1. [이 도메인 작업의 표준 순서]
```

## 주의
- 사업 민감 정보(수익화 전략, 채널 데이터, 키워드 리스트)는 public 리포에
  넣지 않는다. 필요하면 리포를 private으로 전환하거나 로컬 전용
  스킬(~/.claude/skills/)로 분리한다.
