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
`total = missing + new + needsReview + translated + unsupported`.
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
Object keys use camelCase (for example, `needsReview`); status values and CLI
filters retain Xcode spellings such as `needs_review`. The coverage key was
corrected before the initial release of this schema.

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
      "needsReview": 0, "translated": 1, "unsupported": 0
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

## Translation export

```sh
koshops strings export . --language fr
koshops strings export Sources Shared --language fr --language de --status new --status needs_review
koshops strings export A/Labels.xcstrings B/Labels.xcstrings --all-languages --format csv -o translations.csv
koshops strings export . --language fr --status translated --output handoff.json --overwrite
koshops strings export . --all-languages --output - --no-input > handoff.json
```

`strings export` requires either repeatable `--language LANGUAGE` or
`--all-languages`, never both. Source-language units are always excluded per
catalog, even when explicitly selected. Languages must exist in at least one
selected catalog; catalogs without a selected language contribute no records.
It never adds languages. Defaults are `missing`, `new`, and `needs_review`.
Repeated `--status` values replace the defaults and match individual units with
OR semantics. `shouldTranslate: false` entries are always excluded.

Paths, discovery exclusions, ordering, deduplication, and the common selection
root follow inspection's rules above, including explicit catalog selections.
For `A/Labels.xcstrings B/Labels.xcstrings`, the identities are
`A/Labels.xcstrings` and `B/Labels.xcstrings`; for just `A/Labels.xcstrings`, the
identity is `Labels.xcstrings` and the root is `A`. Use the same relative layout
beneath the destination root for a later import. No absolute filesystem location
or selected root is serialized. Catalog text and comments are preserved verbatim;
export does not redact user-authored content.

JSON is the default; `--format json|csv` selects the handoff encoding. This is an
intentional exception to human-readable output by default: export's primary
result is a portable, editable file. It is distinct from inspection's `--json`
report. A `.json` or `.csv` output extension must match the selected format
(case-insensitive), including the default JSON format. A mismatch fails before
writing, even with `--overwrite`, and suggests the matching format or filename.
Extensionless filenames and other extensions do not determine the format.
`--output PATH` / `-o PATH` writes a handoff; omitted output or `-` writes
to stdout. Catalog input still requires paths, not stdin. Success emits only
handoff data to stdout, or a brief file confirmation to stderr when writing a
file. No prompts, color, or terminal decoration are used; `--no-input` is accepted.

Existing output requires `--overwrite`. All records are validated and serialized
before any output. A directory output path is rejected with guidance to provide
a filename, even with `--overwrite`. New files are staged beside the destination and published
with an exclusive hard link, so an existing file cannot be replaced by a race.
Overwrite uses atomic file replacement. Output cannot be a `.xcstrings` file or
a symbolic link. These rules also protect input catalogs from accidental output.
Failure leaves an existing handoff unchanged. Interruption can leave a hidden
`.koshops-export-*` staging file, which can be removed; the final path is either
absent, the old file, or the complete new handoff. Retrying requires `--overwrite`
if publication already succeeded. There is no `--dry-run` for this operation:
stdout is the default preview and catalog files are never edited.

Unsupported destination records within the selected language/exclusion scope
fail even with a status filter, since their status cannot be safely determined.
Selected records also fail for unsupported/missing source context or non-text
comments. Existing nested plural/device leaves are exported separately; absent
sibling variants are never invented. A whole missing destination is rejected
when another localization for that key contains variations/substitutions, even
when the source falls back to the key. An existing empty variant leaf can be
exported as missing because its identity already exists. Unsupported unselected
languages and excluded entries do not prevent export, unless needed as source
context. No subset is emitted on failure.

Exit statuses: `0` success (including an empty selection), `64` invalid command
arguments or missing/conflicting language flags, `1` catalog, language-selection,
unsupported-record, or output failure. Expected failures are actionable stderr
messages with empty stdout. `-h`/`--help` exits `0`; incomplete export explains the
required language flags and points to help.

## Translation handoff contract, version 1

JSON is a UTF-8 object `{"schemaVersion":1,"units":[...]}` followed by a newline.
An empty export has `units: []`. Each unit has all the following fields, including
explicit JSON nulls. Object field order is not significant.

| Field | Type and meaning |
| --- | --- |
| `schemaVersion` | Integer `1`, repeated per record for CSV parity. |
| `catalog`, `key`, `language` | Strings forming identity with `variant`; catalog is relative to the common selection root. |
| `variant` | Ordered array of `{ "dimension": "plural" or "device", "value": "stored case name" }`; `[]` for simple units. |
| `sourceLanguage` | Catalog source language string. |
| `source` | Array of `{ "variant": [...], "text": "..." }` for every source leaf for this key, in inspection order. An absent source localization yields one simple leaf with the key as text. All source variants are provided as context because destination plural categories need not match source categories. |
| `developerComments` | Original comment string, or null when absent; empty string and absence are distinct. |
| `status` | Read-only current status: `missing`, `new`, `needs_review`, or `translated`. |
| `originalTranslation` | Original destination text string, or null when missing. |
| `originalDestination` | Original destination leaf object (`{"stringUnit":{"state":"new","value":"..."}}`), `{}` for an existing empty leaf, or null for an absent localization. |
| `sourceFingerprint` | Lowercase hex SHA-256 of source context, defined below. |
| `destinationFingerprint` | Lowercase hex SHA-256 of `originalDestination`. |
| `recordFingerprint` | Lowercase hex SHA-256 binding all protected record fields, defined below. |
| `translation` | **Editable** string, initially original text or `""` for missing. |
| `statusUpdate` | **Editable** string, initially `""`; explicit updates are only `new`, `needs_review`, or `translated`. `missing` is never writable. |

Only `translation` and `statusUpdate` may be edited. The import contract requires
changed text to have an explicit status update, permits status-only changes,
rejects empty translations, and ignores wholly unchanged records. The original
status never implicitly approves edited text. Import is a subsequent slice;
this command only exports the contract and does not apply edits.

Fingerprint serialization uses Foundation `JSONSerialization` with
`sortedKeys`, `withoutEscapingSlashes`, and `fragmentsAllowed`, UTF-8, no whitespace
or trailing newline, then SHA-256. Version 1's hashed values contain objects,
arrays, strings, nulls, and the integer schema version. No Unicode normalization
is applied. Consumers should treat fingerprints as opaque unless implementing
the same canonical encoding.

The source fingerprint input is an object with `sourceLanguage`, `source`,
`developerComments`, and `sourceLocalization` (the original entire source
localization object, or null for key fallback). This detects source state and
structure changes as well as wording/comments. All source variants of the key
are context for each destination leaf. The destination hash covers only that
leaf, so changing an unrelated destination sibling does not invalidate it.
Unrelated keys, catalogs, and catalog metadata are outside both fingerprints.
The record fingerprint input is the record with `recordFingerprint`,
`translation`, and `statusUpdate` removed. A validator can recompute it to detect
protected-field edits, then compare source/destination fingerprints with live
catalog state and verify the identity, language, structure, and translation
eligibility. Hashes are conflict checks, not cryptographic authentication of a
handoff's author. They do not authorize arbitrary new identities or new languages.

CSV is UTF-8 without a BOM, one header followed by one row per unit, using CRLF
record separators. The columns are exactly the fields in this order:

```text
schemaVersion,catalog,key,language,variant,sourceLanguage,source,developerComments,status,originalTranslation,originalDestination,sourceFingerprint,destinationFingerprint,recordFingerprint,translation,statusUpdate
```

`schemaVersion` is decimal `1`. `variant`, `source`, `developerComments`,
`originalTranslation`, and `originalDestination` cells contain JSON literals;
this preserves null versus empty text and nested structures without additional
columns. All other cells contain their literal string values. Every data cell is
CSV-quoted and embedded quotes are doubled, preserving commas, quotes, CR/LF,
and Unicode. Read the CSV layer first, then JSON-decode the five JSON-valued
columns and parse `schemaVersion` as an integer to recover exactly the JSON unit.
An empty export contains the header only. Spreadsheet editors must retain text
values exactly and must not evaluate cell contents as formulas; no spreadsheet
formula escaping is applied because it would change the handoff's text contract.
