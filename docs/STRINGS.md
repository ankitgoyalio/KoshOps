# String Catalog inspection

```sh
koshops strings languages
koshops strings languages Sources Shared/Labels.xcstrings --json
koshops strings languages . --check-project App.xcodeproj --json
koshops strings list . --language fr --status missing --status new
koshops strings list Localizable.xcstrings --include-excluded --json
```

`strings languages` reports each catalog's source language, languages, and
coverage. `strings list` reports individual units. Both accept any number of
catalog files or discovery directories, defaulting to the current directory.
All inspection is read-only and non-interactive; `--no-input` is accepted.
`-h` / `--help` show usage; an incomplete command group shows help.

## Discovery and identity

Directory traversal skips directories named `.git`, `.build`, `.swiftpm`,
`build`, `Build`, `DerivedData`, `Pods`, `Carthage`, `node_modules`, and `vendor`
at every depth. Discovered symbolic links are skipped, preventing cycles and
unintentional traversal outside the selected tree. Explicit paths (including
symlinks and paths in excluded directories) are honored. Catalogs are
deduplicated by their resolved, standardized paths; hard links are distinct.
No catalogs is an actionable error, rather than an empty success.

A catalog identity is its path relative to the common ancestor of selected
directories and explicitly selected catalogs' parent directories. With no paths,
the root is the current directory. Identities never contain absolute paths;
changing the selection root can change identities. Keys are preserved exactly.
A unit is identified by `(catalog, key, language, variant)`. `variant` is an
ordered array of dimension/value objects from outermost to innermost, preserving
nested plural/device siblings. A simple unit has `variant: []`.

## Languages, states, and coverage

Catalog version `1.0` is supported. Languages are the union of `sourceLanguage`
and every key's localization language names, including excluded entries.
No language is inferred from Xcode unless explicitly comparing declarations.
Language names match exactly; aliases such as `English` and `en` are not merged.

Listing defaults to all catalog languages (including source) and all states.
Repeat `--language` for a union of languages. A language absent from every selected
catalog is a usage error; catalogs without that language contribute no units.
Repeat `--status` for OR matching across `missing`, `new`, `needs_review`, and
`translated`. Filters apply to individual variants, not whole keys.

- `missing`: an absent localization or an empty localization/variant object.
- `new`, `needs_review`, `translated`: the stored `stringUnit.state`, even if
  its text is empty. A stored `new` unit is never reported as `missing`.
- For an absent source localization, the existing key is the source text and
  counts as translated. An explicit source localization uses its stored state.
- A supported localization contains a single `stringUnit`, or one plural/device
  variation dimension at each level, recursively. Every present leaf is one unit.
  Variant names are preserved as stored; language-specific plural requirements
  and absent sibling cases are not inferred from another language's structure.
- Unsupported structures (including substitutions, combined structures, repeated
  dimensions, unknown fields within localizations/string units, and unknown
  states) produce `unsupported` records with an `issue`. The unsupported subtree
  is one record; its children are not also counted. An absent target localization
  with a structured source is unsupported because its variant structure cannot
  safely be inferred. Other absent targets produce one simple missing unit.
- Unsupported records remain visible despite status filters (within selected
  languages and exclusion scope). Inspect these entries in Xcode; they are never
  labeled ordinary translated/new units. Unsupported content is an inspection
  result, not a command failure. Invalid catalog envelopes or malformed entry
  metadata fail the operation before any report is emitted.

`shouldTranslate: false` entries are omitted from the default listing.
`--include-excluded` includes them with `excluded: true`; it never changes coverage.
Coverage counts units per catalog/language, always excluding these entries.
`total = missing + new + needs_review + translated + unsupported`.
Human output shows `translated/total`; consumers can compute that fraction when
`total > 0`. Zero means no eligible units, not 100% coverage. Totals can differ
between languages because variant structures differ. Coverage is a unit count,
not a key count or an assertion of runtime plural completeness.

## Explicit Xcode comparison

`strings languages --check-project PATH` accepts one `.xcodeproj` directory or
`project.pbxproj` file. It reads the root `PBXProject` object's `knownRegions`
and `developmentRegion` through property-list parsing. Their union, excluding
`Base` (a resource region, not a translation language), is compared separately
with each catalog's language set, including the source language. This is a set
comparison; it does not infer target membership or scan other projects.

`catalogOnly` lists catalog languages not declared by Xcode; `projectOnly` lists
Xcode languages absent from that catalog. Both arrays empty means a match.
Mismatches emit the complete primary report plus an actionable stderr diagnostic
and exit 1. Nothing updates the project or the catalogs.

## Stable JSON interface, version 1

Use `--json` for automation. Human wording is not a parsing contract. JSON is
UTF-8, one object followed by a newline, with no decoration or diagnostics.
Arrays are deterministic: catalogs by resolved path, languages and keys
lexicographically, and variant siblings by stored name. Object field order is
not a contract. Optional `value`, `issue`, and `projectCheck` fields are omitted
when absent. Consumers should accept additional fields in version 1.

Languages:

```json
{
  "schemaVersion": 1,
  "catalogs": [{
    "catalog": "Localizable.xcstrings",
    "sourceLanguage": "en",
    "languages": [{
      "language": "fr", "isSource": false,
      "total": 3, "missing": 1, "new": 1,
      "needs_review": 0, "translated": 1, "unsupported": 0
    }]
  }],
  "projectCheck": {
    "declaredLanguages": ["en", "fr"],
    "catalogs": [{"catalog": "Localizable.xcstrings", "catalogOnly": [], "projectOnly": []}]
  }
}
```

`projectCheck` exists only when requested. All coverage counts are nonnegative
integers. The language example shows one row; actual reports include every
catalog language, including the source.

List:

```json
{
  "schemaVersion": 1,
  "units": [{
    "catalog": "Localizable.xcstrings", "key": "Count", "language": "fr",
    "variant": [{"dimension": "plural", "value": "one"}],
    "status": "new", "value": "Un", "excluded": false
  }]
}
```

Every unit contains `catalog`, `key`, `language`, `variant`, `status`, and
`excluded`. Stored/source-fallback units also have a string `value` (possibly
empty). Missing units omit `value`. Unsupported units omit `value` and have an
explanatory string `issue`. No matching units produces `units: []` with exit 0.
Text in human records is JSON-quoted to keep multiline keys and values on one
line and escape terminal control characters.

Exit statuses: `0` successful inspection (including unsupported records), `1`
input/read/schema failure or explicit project mismatch, `64` argument/selection
usage error. Help exits `0`. Failures go to stderr and leave stdout empty,
except project mismatches, which retain the complete requested report.
These commands have no prompts, configuration, environment overrides, network
access, or writes. Cancellation and retries leave input files unchanged.
They operate on identified on-disk catalogs; stdin (`-`) is not accepted because
discovery and catalog identity require paths. Export/import stream contracts are
outside this inspection slice.
