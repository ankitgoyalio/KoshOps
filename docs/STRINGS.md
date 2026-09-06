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
filters retain Xcode spellings such as `needs_review`.

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

## JSON translation export

JSON is the default export format. Use `--format json` explicitly or omit
`--format`. JSON writes to stdout by default, or to `--output PATH`, and requires
no companion manifest. `--manifest` is accepted only with `--format csv`.

```sh
koshops strings export . --language fr
koshops strings export . --language fr --format json -o translations.json
```

The JSON contract is a UTF-8 object
`{"schemaVersion":1,"units":[...]}` followed by a newline. Each unit contains the
fields documented in the record table below. Only `translation` and
`statusUpdate` are editable in a JSON handoff; identity, source context, original
state, and fingerprints remain read-only. Explicit status updates are `new`,
`needs_review`, or `translated`; `missing` is never writable. Changed text requires
an explicit status update; unchanged records are ignored by the future importer.
Empty selections produce `units: []`. JSON stdout remains free of diagnostics on
success. File output requires `--overwrite` to replace an existing file and
rejects `.csv` extensions, directory paths, symlinks, and catalog paths.

## Vendor CSV translation export

```sh
koshops strings export . --language fr --format csv -o translations.csv
koshops strings export . --language ar --status new --format csv -o translations.csv
koshops strings export A/Labels.xcstrings B/Labels.xcstrings --all-languages --format csv -o translations.csv
koshops strings export . --language fr --format csv -o translations.csv --manifest private/manifest.json
koshops strings export . --language fr --format csv --manifest manifest.json --no-input > translations.csv
```

`--format csv` produces **a vendor CSV and a companion JSON manifest**. Send the
CSV to the vendor and retain the manifest locally. The vendor edits only the
`translation` column. The manifest carries catalog identities, original values,
and conflict checks for the future import workflow.

### Selection and context

Require either repeatable `--language LANGUAGE` or `--all-languages`, never both.
Source-language units are always excluded per catalog, even when explicitly
selected. Languages must exist in at least one selected catalog; catalogs without
a selected language contribute no rows. No new languages are inferred. Default
statuses are `missing`, `new`, and `needs_review`. Repeated `--status` values
replace defaults and match individual variants with OR semantics. Entries with
`shouldTranslate: false` are always excluded.

Discovery, ordering, exclusions, and common-root identities follow inspection's
rules above. For `A/Labels.xcstrings B/Labels.xcstrings`, manifest identities are
`A/Labels.xcstrings` and `B/Labels.xcstrings`; selecting only `A/Labels.xcstrings`
makes the identity `Labels.xcstrings` beneath root `A`. Retain that relative
layout for a later import. No absolute filesystem paths are serialized as
metadata. User-authored text and developer comments are preserved verbatim.

Unsupported destination records within the selected language/exclusion scope
fail even with a status filter because their status is unknown. Selected records
also fail for unsupported/missing source context or non-text comments. Existing
nested plural/device leaves are selected individually; absent sibling variants
are never invented. A whole missing destination is rejected when another
localization for the key contains variations/substitutions, even if the source
falls back to the key. Existing empty variant leaves can be exported as missing.
Unsupported unselected languages and excluded entries do not prevent export,
unless needed as source context. No subset is emitted on failure.

### Files, streams, and safety

`--output PATH` / `-o PATH` selects the CSV file. The default manifest path is the
complete output filename plus `.manifest.json`, for example
`translations.csv.manifest.json`. `--manifest PATH` overrides it; the parent
directory must already exist. This lets you retain metadata in a separate folder.

Omitted output or `--output -` emits CSV to stdout and requires `--manifest PATH`.
The manifest cannot use stdout. Diagnostics and confirmation of the manifest
location go to stderr; stdout contains only CSV. No prompts or decoration are
used; `--no-input` is accepted. Catalog input still requires on-disk paths.

The CSV and manifest must use separate regular-file destinations. Directory,
symbolic-link, catalog (`.xcstrings`), and conflicting extension destinations
fail with actionable guidance. Recognized `.csv`/`.json` extensions are checked
case-insensitively against each file's role, even with `--overwrite`. CSV requires
`.csv` and the manifest requires `.json`. Extensionless filenames and other
extensions are permitted; they never select the encoding.

If either destination exists, `--overwrite` is required. Both paths are checked,
existing files backed up, and both outputs staged before publishing. Handled
publication failures restore earlier writes; recovery failures report the
retained backup path. File publication is atomic individually, not across both
files. Interruptions can leave `.koshops-export-*` staging files and
`.koshops-backup-*` copies beside the outputs, or a mixed old/new pair. Keep any
backups needed for recovery, regenerate the pair before sharing, and remove
leftovers only after checking both files. Do not replace a manifest while its
CSV is with a vendor. Keep each issued pair until its return is processed.
For stdout, the manifest is saved before emitting CSV; an interrupted or broken
pipe may yield incomplete CSV, which must be regenerated.

There is no catalog mutation or `--dry-run` in export. Exit `0` means success,
including an empty selection (CSV header and an empty manifest). Exit `64` means
invalid arguments, conflicting/missing language flags, unsupported format, or
stdout without a manifest path. Exit `1` means catalog, language-selection,
unsupported-record, or file failure. `-h`/`--help` exits `0`.

### Vendor CSV contract, version 1

UTF-8 without BOM, CRLF record separators, one row per selected unit. Every cell
is quoted; embedded quotes are doubled. Commas, quotes, CR/LF, and Unicode survive
CSV decoding. The header is exactly these five field names:

| Column | Meaning |
| --- | --- |
| `id` | Opaque stable record reference; do not edit. |
| `language` | Target language; do not edit. |
| `source` | Read-only source text. Simple sources are verbatim. Structured sources include all source leaves, each prefixed by `[dimension=value/...]` and separated by newlines. |
| `context` | Read-only target variant label (`Target variant: dimension=value/...`) followed by developer comments, separated by a newline when both exist. |
| `translation` | The only editable field; initially existing destination text, or empty for missing. |

IDs are `u-` followed by the protected record fingerprint. They differ across
catalogs, keys, languages, and variants and change when protected source or
destination state changes. Row order does not define identity. The prefix keeps
IDs textual in spreadsheet tools. Do not edit IDs or context, and retain all five
columns. Missing/omitted rows must never imply deletion in a future importer.
No Xcode statuses, catalog paths, fingerprints, or nested JSON cells are exposed
to the vendor. Structured source context is descriptive; it never guesses a
mapping between different source and target plural categories.

CSV content is literal text. Spreadsheet editors must retain it as text rather
than evaluate formulas or coerce values; formula escaping is not applied because
it would change translations. Vendors need not see or modify the manifest.

### Companion manifest contract, version 1

UTF-8 JSON followed by a newline:

```json
{
  "schemaVersion": 1,
  "kind": "vendorManifest",
  "entries": [
    {"id": "u-...", "source": "Source text", "context": "Developer comment", "record": {}}
  ]
}
```

The example omits `record` contents for brevity; each real `record` has every field
in the following table. Entry `source` and `context` are the exact original CSV
cells. The corresponding original `language` and `translation` are in `record`.
`id` must equal `u-` plus `record.recordFingerprint`. Thus the manifest retains
every original CSV cell and the detailed catalog state without burdening vendors.
All manifest fields are read-only; schema field names are camelCase.

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
| `translation` | Editable in JSON export; read-only baseline in the manifest. Initially original text or `""` for missing. |
| `statusUpdate` | Editable in JSON export; blank read-only baseline in the manifest. Explicit updates are only `new`, `needs_review`, or `translated`. `missing` is never writable. |


### Future import requirements

Import is not yet implemented. For CSV, the returned file and its original manifest will
both be required. An importer must match IDs, reject unknown/duplicate IDs and
protected-cell edits, verify the manifest and live catalog fingerprints, then
apply only deliberate translation changes. The manifest's reserved `statusUpdate`
is blank; vendors never set it. A future explicit import option such as
`--status-update needs_review` will choose the state for changed translations.
That option is a planned contract, not an available command today. Changed text
must never inherit the exported original approval. Unchanged or omitted records
must remain untouched; all normal import validation still applies.

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
