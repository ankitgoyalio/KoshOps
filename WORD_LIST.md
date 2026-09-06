# KoshOps word list

Use this reference when drafting, reviewing, naming, or implementing CLI copy.
Alternatives in **Avoid** apply to the same concept, not to every use of a word.

## Voice

Write as a clear, practical colleague helping developers prepare translations.
Lead help with examples, describe file effects before an action, and end errors
with a supported recovery step. Completion messages distinguish exported files
from proposed and applied catalog changes.

## Terminology

| Use | Avoid | Definition |
| --- | --- | --- |
| Catalog | — | An Xcode String Catalog (`.xcstrings`). Name the extension when explaining input paths. |
| Translation | Translation unit when the distinction is unnecessary | The user-facing term for translated text. Use **translation unit** when distinguishing a key from an individual plural or device variant. |
| Handoff | Handoff without an introduction | An exported translation file. Introduce it as JSON or CSV for editing. |
| Companion manifest | `vendorManifest` in explanatory copy | The JSON file retained from a CSV export to validate returned translations. It is required for CSV import and is not for editing. Preserve `vendorManifest` as the JSON `kind` value. |
| Preview | Applied, imported when only a preview completed | Validated, proposed catalog changes. Say “No catalogs changed” after a preview. |
| Apply changes | Application | Write validated translations to one catalog. Omit `--dry-run` to apply; confirm applied changes only after replacement succeeds. |
| Review status | Review intent | The status chosen for a changed translation: `new`, `needs_review`, or `translated`. Use `statusUpdate` in JSON and `--status-update` for CSV. |
| Needs review | `needs_review` in prose | The readable status name. Preserve `needs_review` for status values, record labels, and command arguments so users can copy the exact value. |
