# Coding standards

## JSON naming

Always use camelCase for JSON field names in KoshOps schemas, including nested
objects. For example, use `schemaVersion`, `sourceLanguage`, and `needsReview`.
Apply this convention consistently in implementation, tests, and documentation.

This rule governs schema field names. Preserve user-provided keys, string values,
and external format contracts such as Xcode String Catalogs verbatim.

## Export filenames

Validate recognized output file extensions against the selected export format,
including the default format. Compare extensions case-insensitively: `.json`
requires JSON and `.csv` requires CSV.

Reject mismatches before creating or replacing any file, even with `--overwrite`.
Explain the mismatch and suggest the matching format option or a corrected
filename. Never silently change the selected format or rename the output.

Allow extensionless filenames, unrecognized extensions, and stdout (`-`); the
selected format determines their content.

## Release-aware compatibility

Before changing existing behavior, always check this repository's GitHub Releases
with `gh release list` and inspect the relevant release tags to determine whether
the affected feature has shipped. A version string, commit, or tag alone is not
evidence of a release; draft releases do not count as shipped.

Add compatibility fallbacks, deprecation notices, or migration guidance only
when the affected behavior is present in a published release. If the feature has
not been released, treat it as new: implement and document the intended behavior
directly, without legacy modes or references to superseded implementations.

If release information cannot be retrieved, report that uncertainty rather than
assuming the feature is unreleased.
