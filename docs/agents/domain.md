# Domain docs

## Layout and reading rules

This repository uses a single-context layout:

- `CONTEXT.md` at the repository root: domain concepts and vocabulary.
- `docs/adr/`: architecture decision records.

Before exploring domain behavior, read `CONTEXT.md` and ADRs relevant
to the area being changed.

If these files or directories are absent, proceed silently. Create domain
documentation when terms or decisions are resolved through domain work.

## Vocabulary

Use terms defined in `CONTEXT.md` when naming domain concepts in issues,
proposals, code, and tests. If a needed concept is missing, reconsider the
term or note the glossary gap during domain work.

## Decision conflicts

If a proposal contradicts an existing ADR, identify the ADR and explain
why the decision should be reconsidered.
