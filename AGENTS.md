# KoshOps agent guide

KoshOps is a Swift CLI for Xcode asset management, currently focused on String
Catalog inspection and translation exchange.

## Task routing

- **Code:** Before implementation or review, read
  [`CODING_STANDARDS.md`](CODING_STANDARDS.md), including its release check before
  changing existing behavior.
- **CLI:** Before changing or reviewing command syntax, output, errors, prompts,
  exit behavior, configuration, environment variables, or CLI documentation, read
  [`docs/CLI_DESIGN.md`](docs/CLI_DESIGN.md). Satisfy every applicable checklist
  item; document intentional exceptions beside the change.
- **CLI copy and naming:** Before planning, reviewing, or editing, use
  [`app-ux-writing`](.agents/skills/app-ux-writing/SKILL.md). Read and maintain
  [`WORD_LIST.md`](WORD_LIST.md) for shared voice and terminology decisions.
- **Localization:** Before changing or reviewing catalog discovery, inspection,
  export, import, or exchange schemas, read [`docs/STRINGS.md`](docs/STRINGS.md)
  for the behavior contracts.
- **Domain:** Before exploring domain behavior or writing domain documentation,
  read [`docs/agents/domain.md`](docs/agents/domain.md).
- **Issues and specs:** Before tracker operations, read
  [`docs/agents/issue-tracker.md`](docs/agents/issue-tracker.md).
- **Triage:** Before triaging, read
  [`docs/agents/triage-labels.md`](docs/agents/triage-labels.md).

## Working agreement

- Keep domain behavior separate from `ParsableCommand` adapters so it can be
  tested without invoking a process.
- Preserve unrelated working-tree changes.

## Subagents

For every spawn, including nested subagents, explicitly pass the model and
reasoning effort from `[agents]` in [`.codex/config.toml`](.codex/config.toml).
Use `fork_turns="none"` with a self-contained brief or a bounded history fork.
Change these settings only at the user's explicit request.

## Completion

- Add behavioral tests for user-visible success and failure paths; cover help
  and parsing when the command surface changes.
- Run `swift test` for every code change and resolve failures before completion.
- For CLI-surface changes, inspect affected `--help` output and exercise
  representative success, user-error, and non-interactive paths as applicable.
