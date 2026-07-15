# Dependency Graph

## Execution Order
1. Milestone 1: Fix All 9 Issues (no dependencies — single self-contained milestone)

## Notes
All 9 issues are independent fixes that can be applied in a single pass. There are no dependencies between them:
- Issues 1, 2, 3 are template-only changes
- Issues 4, 5, 6 are logic changes in different files
- Issues 7, 8, 9 are configuration/edge-case fixes

The full test suite (`bundle exec rspec`) acts as the regression net after all fixes are applied. New specs added for Issues 1 and 4 validate behavior changes in isolation.

Suggested fix order within the milestone (for clean commit history):
1. Template fixes (Issues 1, 2, 3) — presentation layer
2. New spec additions for Issues 1 and 4 — establish expected behavior
3. Logic fixes (Issues 4, 5, 6) — business logic
4. Map generator fix (Issue 8) — categorization
5. Orchestrator output fix (Issue 9) — message formatting
6. Version bump (Issue 7) — always last
7. Run full test suite
