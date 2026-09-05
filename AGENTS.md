# KoshOps agent guide

KoshOps is a human-first Swift CLI for automating Xcode asset management. Treat
its command surface as a product interface used both at a terminal and in
scripts.

## Task routing

- For any change or review involving commands, arguments, flags, help, output,
  errors, prompts, exit status, configuration, environment variables, or CLI
  documentation, read [`docs/CLI_DESIGN.md`](docs/CLI_DESIGN.md) before deciding
  on behavior. Apply every relevant item in its review checklist.
- Use Apple's Swift Argument Parser for command structure and parsing. Inspect
  `Package.swift` and the existing command types rather than duplicating package
  details here.

## Working agreement

- Preserve unrelated working-tree changes; this repository may be under active
  construction.
- Keep domain behavior separate from `ParsableCommand` adapters so it can be
  tested without invoking a process.
- Keep public CLI behavior deliberate and consistent across subcommands. Treat
  command names, flags, structured output, exit codes, configuration keys, and
  environment variables as compatibility commitments.
- Add behavioral tests for user-visible success and failure paths. Cover help or
  parsing behavior when the command surface changes.

## Completion

Run `swift test` for every code change. For a CLI-surface change, also inspect
the affected `--help` output and exercise representative success, user-error,
and non-interactive paths as applicable. The task is complete when tests pass
and every relevant item in `docs/CLI_DESIGN.md` is satisfied or an intentional
exception is documented beside the change.

## Agent skills

### Issue tracker

Track issues and specs in GitHub Issues. Before issue operations, read
`docs/agents/issue-tracker.md`.

### Triage labels

Use the five canonical triage labels. Before triaging, read
`docs/agents/triage-labels.md`.

### Domain docs

Use a single-context layout. Before exploring domain behavior, read
`docs/agents/domain.md`.
