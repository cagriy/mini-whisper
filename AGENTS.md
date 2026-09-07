# Project instructions

Read `CLAUDE.md` for the repository architecture, development commands, and conventions.

## Standing user requirements

- Always use test-driven development for implementation: write the behavior test
  first, run it, and observe the expected failure before writing production code.
- Confirm the failure is caused by the missing behavior, not an unrelated build,
  environment, or fixture error. For a new API, a missing-symbol failure establishes
  the initial red; get a meaningful behavioral failure with minimal scaffolding
  before implementing the behavior.
- Implement the smallest change that passes, rerun the focused test and surrounding
  suite, then refactor while keeping tests green.
- Always check finished work: review the final diff, run the relevant regression
  suites and build checks, and exercise changed user flows where possible.
- Report what was actually verified, including the observed initial failure and
  final result. Explicitly identify anything that could not be verified.
- Planning and documentation changes still require a final consistency and diff
  review; do not claim runtime tests were run when only documents changed.

These requirements were stated by the user on 2026-09-05 and apply to subsequent
work in this repository. They take precedence over weaker testing exceptions in
older project plans.
