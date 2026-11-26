# REST client and extension contract

`catalog/endpoints.json` defines approved operations outside `Invoke-VbrRestRequest`. Native helpers are private to the pack module. Tests call the shared handler by operation ID and validated parameters, not arbitrary URLs.

Transport enforces one HTTPS origin, OS certificate/hostname trust, pinned `1.3-rev2`, GET-only reads, separate token/refresh/logout POSTs, no redirects/proxies/default credentials, bounded retry, cancellation and response limits. Tokens remain in private module memory. Maester state holds only a generation handle, expiry and a bound non-secret assessment entry point; Describe excludes client, tokens and cache.

“Private module” is not a security isolation boundary: trusted PowerShell code in the same process can inspect module state. The callback's source/serialization contains no credentials, but a pack is not a sandbox. The connector lifecycle and successful TLS interoperability are implemented, not yet qualified by these tests.

## Add a test or endpoint without editing the handler

1. Reuse a registered operation, or add a reviewed catalog definition: ID/version/revision, relative route, parameter constraints, read method, representation, response/request adapters, completeness/identity fields, permission/sensitivity metadata and TTL.
2. Register reviewed `ConvertFrom-Vbr<Name>` and, for a new paging convention, `Get-Vbr<Name>Parameters` helpers in pack source. Command references are captured and checked at load, not resolved anew at each request. Response adapters return Data, Total, Done and NextState. Request adapters translate bounded paging state into parameters validated against the registered route. Definitions and code cannot be injected through runtime configuration or API responses.
3. Normalize typed capabilities separately from raw schema paths; evaluate equivalent Agent/VMware/Hyper-V evidence through common policy functions.
4. Add synthetic fixtures, permission mapping and contract tests. The suite demonstrates both a new endpoint and a new cursor paging strategy without changing handler source.

Unknown registrations/revisions, route escapes, invalid parameters, duplicate identities, changing totals, nonprogressing pages or incomplete evidence fail explicitly. A pagination adapter cannot supply an arbitrary next URL or bypass the same origin/route checks. Changing authentication, allowed verbs, origins or wire protocol needs architectural approval, not a catalog-local override.

JSON, text and bounded binary representations are supported by the adapter interface; only complete validated JSON evidence is cacheable. Current staging caps are 4 MiB per response and 32 MiB per collection, 100,000 items and 1,024 pages. Exceeding a limit is Error, never partial success. Default logical deadline is 60 seconds (maximum 300), with at most two transient GET retries and one 401 refresh budget across all pages. Retry-After does not extend the deadline.

## Cache lifecycle

Direct `Invoke-Maester` / `Invoke-MtTest` calls remain uncached. To enable assessment-scoped caching, dot-source `public/Invoke-VbrAssessment.ps1` from the approved installed pack folder, then call `Invoke-VbrAssessment`. The connector's bound entry point enters the same native private module; this is verified against the pinned engine, not an assumed lifecycle hook.

The wrapper runs only VBR with built-in tests disabled and always clears its unique scope in finally. Nested/concurrent scopes are rejected. Cache identity includes connection generation, principal/profile, origin/server identity, operation and resolved route/query, revision, representation, request/response adapter and contract versions. Cached JSON is reparsed on retrieval so caller mutation cannot corrupt later evidence. Reconnect/logout and errors invalidate cache; unchanged-scope token renewal can retain valid entries.

Limits: 128 entries and 32 MiB serialized payload accounting, not a heap bound. TTLs: infrastructure 300 seconds, identity/security 60 seconds, volatile evidence 30 seconds. No disk cache or stale-on-error. `-BypassCache` on the internal handler forces collection; freshness/session controls request fresh evidence. Acquisition/completion timestamps identify a collection interval, not an atomic snapshot.
