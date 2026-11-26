# Implementation status

Plan `3a1bc37` was explicitly approved on 2026-11-26. Offline build work is authorized. **The next approval is required before any Azure provisioning or spend.** No Azure resources, VBR accounts or production settings have been changed.

## First offline milestone

- Native connector; strict GET-only REST transport and separate authentication lifecycle.
- Declarative endpoints and reviewed request/response adapters; extension does not require REST-handler edits.
- Common capability normalization for managed Windows/Linux Agent, VMware and Hyper-V backup jobs.
- Scoped, bounded, copied evidence cache; direct native invocation uncached.
- 17 paired native controls, explicit inventory, policy settings, permission catalog and generated matrix.
- Pinned offline CI; synthetic unit/contract and installed native-engine validation.

Verified so far: native pack validation, synthetic common/transport contracts, native six-outcome mapping, GlobalSettings/runtime precedence, cache sharing across selected tests, independent assessment runs and uncached direct native calls. Final review and follow-up validation results belong to the build report; this document does not assert complete acceptance.

Latest combined local validation: `Test-MtPack` valid with 17 native tests; **27 Pester tests passed, zero failed**; installed native outcome/precedence/cache checks passed. See [the milestone build report](build-report.md). Public CI has been authored but has not been run on GitHub.

Opus review returned PASS for this first offline milestone only, not release or Gate B/C/D. Connector lifecycle tests, a TLS positive-control test, repository-source installation and further edge-case qualification remain open. Controlled error codes are preserved; session collection uses the public-schema `jobIdFilter` per expected job, not an assumed `jobId` query.

## Not completed / not qualified

Gate B remains partial: the official public `1.3-rev2` schema was recovered from Veeam's versioned reference, but target-installed Swagger, edition capabilities, custom permission IDs and live object visibility are unverified. Agent minimum-core live feasibility is not proven by fixture tests.

Additional planned controls (MFA and service-account exception ownership/expiry, role approvals, malware/prerequisites/updates, notifications, analyzer freshness/findings/suppression and syslog) are not implemented in this milestone. Weekly health scheduling, complete per-job/object coverage mapping, broader outcome/overlay edge cases, full-stream secret redaction and real TLS/mock-server fault testing also need further offline work. Do not treat missing controls as compliant or claim the full plan is built.

Azure IaC/orchestration, SSH bootstrap, independent janitor and cost/cleanup preflight remain preparation work; none has been provisioned or executed. Private live integration/E2E and optional restore qualification remain future, separately gated evidence.
