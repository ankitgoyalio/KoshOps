# Issue tracker: GitHub

Issues and specs live in GitHub Issues for `ankitgoyalio/KoshOps`.
Use the `gh` CLI from this repository; it infers the repo from the remote.

## Operations

- Create: `gh issue create --title "..." --body-file <path>`
- Read: `gh issue view <number> --comments`; fetch metadata with
  `gh issue view <number> --json number,title,body,labels,state`.
- List: `gh issue list --state open --json number,title,body,labels,comments`;
  add label and state filters as needed.
- Comment: `gh issue comment <number> --body-file <path>`
- Label: `gh issue edit <number> --add-label "..."` or `--remove-label "..."`
- Close: `gh issue close <number>`

Write multiline issue bodies and comments to a temporary file and pass
its path with `--body-file`.

When a skill says “publish to the issue tracker,” create a GitHub issue.
When it says “fetch the relevant ticket,” read the issue and its comments.

## Pull requests as a triage surface

**PRs as a request surface: no.**

GitHub issues and PRs share a number space. If a reference is ambiguous,
resolve it with `gh pr view <number>`, falling back to `gh issue view <number>`.
