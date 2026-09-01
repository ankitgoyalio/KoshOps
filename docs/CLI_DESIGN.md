# KoshOps CLI design standard

This standard adapts the [Command Line Interface Guidelines](https://clig.dev/)
for KoshOps. The goal is a CLI that feels helpful to people while remaining a
predictable component in scripts. Use clig.dev for deeper rationale and
examples; use this document for repository decisions and review.

## Product principles

1. **Human-first.** Choose safe, useful defaults and explain state changes in
   plain language. The user should know what happened and what to do next.
2. **Composable.** Preserve conventional streams, exit statuses, signals, and
   line-oriented or structured data so commands work in pipelines and CI.
3. **Discoverable.** Make syntax guessable, lead help with realistic examples,
   and turn errors into concise guidance.
4. **Responsive and robust.** Validate before mutating, acknowledge slow work
   quickly, support interruption, and make retries safe where practical.
5. **Intentional compatibility.** Prefer established conventions. When KoshOps
   needs to differ, record why and keep the resulting interface stable.

## Command surface

- Build commands with Swift Argument Parser. Every command and subcommand
  supports `-h` and `--help`; reserve `-h` for help and `--version` for version.
- Running an incomplete command prints concise help rather than a parser dump or
  a silent failure. Full help includes a one-line purpose, usage, common options,
  realistic examples, and the most useful next step.
- Use lowercase, memorable command names. Use full-word long flags with standard
  meanings. Add a short flag only for a frequent operation with an obvious,
  unambiguous letter.
- Prefer a named option when a positional value would be unclear or constrain
  future evolution. Positional arguments are appropriate for the command's
  obvious primary objects, including a list of equivalent paths.
- Keep equivalent names and output conventions consistent across subcommands.
  Avoid ambiguous command pairs, implicit catch-all commands, and arbitrary
  subcommand abbreviations.
- Make the default path work for most users. Interactive convenience may
  supplement flags and arguments, but every operation must remain fully usable
  without prompts.

## Output and exit behavior

- Send the command's primary result to `stdout`. Send progress, explanations,
  warnings, and errors to `stderr`. Never mix commentary into structured data.
- Exit with `0` only when the requested operation succeeds. Use non-zero statuses
  for failures, keeping stable distinctions only when callers can act on them.
- Default to concise, human-readable output and confirm state changes. When a
  stable machine interface is needed, provide `--json`; provide `--plain` for
  line-oriented text when human formatting would break pipelines.
- Treat documented `--json` schemas, `--plain` records, and exit statuses as
  versioned interfaces. Tests should parse structured output rather than compare
  cosmetic human formatting byte-for-byte.
- Adapt presentation to the destination. Suppress animation and decorative
  formatting when the relevant stream is not a TTY. Color, when introduced,
  must honor `NO_COLOR`, `TERM=dumb`, and `--no-color`.
- Keep successful output brief. For long-running work, acknowledge the operation
  promptly and show useful progress on a TTY without polluting redirected output.
  `--quiet` may suppress non-essential messaging; diagnostic detail belongs
  behind `--verbose` or `--debug`.

## Errors and safety

- Validate all user-controlled input before changing files. Rewrite expected
  failures as concise messages that state the problem, relevant context, and a
  concrete recovery step. Put the most actionable information last.
- Expected failures never expose a Swift backtrace. Unexpected failures should
  preserve diagnostic context and identify a support path without overwhelming
  normal output.
- Suggest likely corrections, but never silently reinterpret input for an action
  that changes state.
- Make external effects explicit, especially unexpected file access or network
  activity. Describe what changed after a successful mutation.
- Design mutating operations to be idempotent or recoverable. For consequential
  or bulk changes, offer `--dry-run`. Require deliberate confirmation for
  destructive work while retaining a documented non-interactive form such as
  `--force` or a value-specific confirmation flag.
- Respond promptly to Ctrl-C. Leave data consistent, bound cleanup time, and make
  a retry safe whenever the underlying operation permits it.

## Input, configuration, and secrets

- Prompt only when `stdin` is a TTY. Honor `--no-input`; if required information
  is missing, fail with the exact flag or argument the caller should provide.
- Support `-` for stdin or stdout when a command naturally reads or writes a
  file-shaped stream.
- Apply configuration precedence from most to least specific: flags,
  environment, project configuration, user configuration, system configuration.
  Use `KOSHOPS_` for KoshOps-specific environment variables and uppercase ASCII
  names with underscores.
- Accept secrets through protected files, stdin, platform credential storage, or
  another purpose-built channel. Command arguments, ordinary environment
  variables, logs, and error messages are not secret channels.
- Ask before modifying configuration owned by another tool and report the exact
  files affected.

## Compatibility and distribution

- Evolve public interfaces additively when practical. Before removing or
  changing one, emit a targeted deprecation message that shows the replacement
  and allow enough time for scripts to migrate.
- Human-readable wording may improve over time; automation must use the stable
  structured or plain interface.
- Prefer a self-contained executable, leave a small footprint, make uninstalling
  straightforward, and never collect usage or crash data without informed
  consent.

## Review checklist

For every CLI-facing change, verify all applicable statements:

- The common case is obvious from the command name, defaults, help, and examples.
- `-h`, `--help`, incomplete invocation, and invalid input produce useful output.
- Primary results, messaging, and failures use the correct streams and statuses.
- Piped or redirected execution contains no prompts, animation, color escapes,
  or commentary mixed into machine-readable output.
- Errors identify the problem and give an actionable recovery step without a
  backtrace for expected failures.
- File changes, network access, and destructive effects are explicit, safe to
  preview when warranted, and followed by a clear result.
- Interruptions, partial failure, retries, and repeated invocations leave a
  coherent state.
- New flags, names, output formats, configuration, and environment variables are
  conventional, consistent, documented, and covered by behavioral tests.
- No secret can leak through arguments, environment, output, logs, or diagnostics.
- Any deliberate departure from this standard records its user benefit and
  compatibility impact in code comments, tests, or adjacent documentation.
