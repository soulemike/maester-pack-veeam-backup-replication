# First offline milestone — 2026-11-26

## Outcome

The approved plan's first offline implementation milestone is built and locally validated. This is **not the full plan, a release, or Gate B/C/D acceptance**. No Azure resources were provisioned, no VBR account/settings were changed, and no live VBR assessment ran. Publication was subsequently authorized by the user's explicit commit-and-push request; consult Git history for the published revision.

## Validation evidence

- Pinned bootstrap: Maester `3.0.0-rc83`, Pester `5.7.1`, Microsoft.Graph.Authentication `2.27.0`; package hashes in `qa/versions.json`.
- Clean distributable `Test-MtPack`: valid, 17 paired native controls. Direct networking/dynamic-dispatch risk findings are disclosed, not suppressed.
- Combined local Pester run after review fixes: **27 passed, 0 failed**.
- Locally installed native engine: Passed, Failed, Investigate, Error, Skipped and NotRun outcomes checked; GlobalSettings and selected runtime precedence checked.
- Native cache contract: two controls shared one request within an assessment; a second assessment acquired independently; direct native calls stayed uncached.
- Synthetic secret markers were absent from checked native JSON/HTML/Markdown artifacts and connection metadata/Describe. This does not establish full-stream redaction or connector lifecycle qualification.
- Endpoint and new cursor-pagination extension tests passed without REST-handler source changes. Duplicate/changing/empty pagination, invalid parameters, response limits, cancellation, bounded retry and 403 behavior were checked.

Synthetic artifacts and copied bundles are retained only under ignored `.tools/` inside this project. No task-owned worker, server, or background job is intentionally retained.

## Review

Opus returned **PASS for this first offline milestone only**. Follow-up fixes preserve safe Error codes, avoid reporting unknown raw session result strings, capture validated adapter commands at load, and use schema-verified per-job `jobIdFilter` session collection. Failed connection cleanup now attempts logout for an issued token; token renewal updates the native expiry metadata. These lifecycle changes still need lifecycle tests.

Open review items: connector password login/smoke/renew/logout integration, positive-control TLS interoperability, repository-source installation, large-history behavior, and broader correlation/override/error-stream cases. Tool-folder reuse now checks extracted files against the pinned archive rather than trusting an existing directory. Current negative TLS coverage is not independent proof of correct TLS interoperability.

## Next work

Continue authorized offline development: complete the planned security/notification/analyzer controls and permission mappings, expand lifecycle/schema/policy tests, then prepare the private Azure preflight/SSH bootstrap/janitor/cost/cleanup assets. Before any Azure provisioning, obtain the user's next explicit approval covering that preflight. Target-installed Swagger, edition availability and live RBAC/object-visibility evidence remain pending.
