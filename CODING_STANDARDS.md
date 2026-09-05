# Coding standards

## JSON naming

Always use camelCase for JSON field names in KoshOps schemas, including nested
objects. For example, use `schemaVersion`, `sourceLanguage`, and `needsReview`.
Apply this convention consistently in implementation, tests, and documentation.

This rule governs schema field names. Preserve user-provided keys, string values,
and external format contracts such as Xcode String Catalogs verbatim.
