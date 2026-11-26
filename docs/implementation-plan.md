# VBR assessment pack implementation plan

**Status: PROPOSED — awaiting user approval.** This document is a plan, not an implementation report. The plan must be committed and pushed, then explicitly approved by the user before implementation begins. Publication and technical review do not satisfy that approval gate. No implementation, provisioning, or tests are authorized by this plan alone.

## 1. Purpose and scope

Build a Maester pack that assesses Veeam Backup & Replication (VBR) implementation state, configuration state, operational posture, and security posture through its REST API. The target is workload-agnostic assessment of VBR-managed jobs on VBR 13.1, REST API 1.3-rev2, with Agent, VMware, and Hyper-V adapters for the common protection capabilities. The pack must report evidence and uncertainty honestly; it must not imply that configuration checks prove successful recovery, immutable copies, or overall compliance.

The initial release is to include the pack foundation, shared API collection/evaluation path, core assessment controls, documentation, and a private Azure deployment end-to-end (E2E) qualification using a representative VBR job (a small VBR-managed Veeam Agent backup job is preferred). It is not a requirement to stand up a live VMware or Hyper-V environment for this E2E gate. VMware and Hyper-V schemas and branches must still have offline fixture/contract coverage. The live scenario qualifies only if it exercises the shared production collection and evaluation path and the minimum core-check set defined at Gate B; a backup job for which every relevant check is skipped is not representative coverage.

V0.1 includes only the minimal representative job/session/restore-point adapter needed for deployment E2E and shared controls. It does not imply full Veeam Agent product coverage, standalone-agent support, or a separate Agent policy assessment suite.

Hypervisor support is not a prerequisite of the actual Veeam posture checks. Agent, VMware, and Hyper-V jobs belong to the same capability-based assessment scope: apply the same controls, policy defaults, runtime overrides, and verdict semantics wherever the VBR API supplies equivalent protection evidence. A hypervisor is workload metadata, not a gate for server-wide checks or common job checks. Document genuinely different capabilities or evidence limitations rather than building separate hypervisor-specific baselines or requiring a vCenter/Hyper-V connection for generic checks.

VMware and Hyper-V adapters, like the Agent adapter, are limited in v0.1 to mapping the common protection model. Hypervisor-only product features are outside v0.1 unless separately approved and are recorded as scope limitations; their presence does not require broader checks than the Agent scenario.

This plan does not authorize changes to business logic, account configuration, Azure resources, or any other implementation. It does not authorize a spend, elevated access, production changes, or destructive testing. Those require separate approval and preflight. The current repository is a scaffold: preserve its package identity and do not claim that planned functionality is already present.

## 2. Repository invariants and current state

- Preserve pack ID `soulemike.veeam-backup-replication`, GUID `4b7eb326-ab02-48cd-a00e-d7eeb1e3ff20`, code `VBR`, and the current `RequiresMaester >= 3.0` requirement.
- Preserve the existing test placeholder ID `MP.VBR.1001`; after approval, repurpose it as a VBR server compatibility control rather than renumbering it.
- The manifest has an empty service/network declaration and references a placeholder `maester-pack.guide.json`. The guide, connector, and remaining product documentation are future implementation deliverables; do not represent proposed content as implemented.
- Current tests are a placeholder, not evidence of functionality or test success.
- Implementation control IDs: `1000–1999`; configuration `2000–2999`; operations `3000–3999`; security `4000–4999`. Use distinct controls for distinct assertions; a candidate catalog of roughly 25–30 controls is a planning estimate, not an implemented or immutable count.

## 3. Decision history and corrections

1. The initial direction targeted VBR 13.1 and REST API 1.3-rev2, with a preference for a low-cost Azure lab and Microsoft Entra managed identity (MI) for Azure-side operations.
2. A prior review blocked public live testing and reliance on an assumed native cache hook, and called out an incorrect claim that Maester lacked an Investigate outcome. The corrected design confines live VBR assessment to private Azure execution and uses the documented native outcome model. It proposes pack-owned, opt-in assessment scoping rather than assuming a Maester run-ID/cache hook. This history does not establish approval of the final plan.
3. The latest user correction makes the E2E target the VBR deployment itself, not a protected hypervisor. A VBR-managed Agent backup of a small Azure VM is the preferred representative job. No vSphere, AVS, nested ESXi, or nested Hyper-V lab is required. VMware/Hyper-V paths remain subject to schema/fixture contract tests, but must not be described as live-tested unless that evidence is separately obtained.
4. The representative Agent scenario must cover the shared collection and evaluation path and exercise core checks. Merely completing a backup while all pertinent job checks are skipped does not meet the E2E acceptance gate.
5. A genuine VMware E2E lab is not a release prerequisite. This latest decision supersedes earlier review-gate language suggesting live hypervisor E2E coverage.
6. Before selecting the Agent job topology, implementation must verify the target API schema, endpoint fields, and edition availability. Any VMware/Hyper-V-only feature not represented by the Agent scenario must be separately recorded as contract-covered or unavailable in that live profile—not falsely reported as live-covered.

A VBR-managed Agent job on a small Azure VM is preferred, not mandatory. Any other approved representative, core-capable VBR job hosted entirely in Azure may be selected if Gate B evidence shows it exercises the shared core path. The selected job must not introduce a requirement for a VMware, Hyper-V, AVS, or nested-hypervisor lab.

The subsequent clarification makes generic, capability-based API processing a normative design requirement and selects SSH as the preferred guest-management protocol after Azure resources are provisioned. Neither change authorizes implementation before Gate A.

## 4. Evidence baseline and verification caveats

The following was checked on 2026-11-25 as planning evidence, not as a substitute for revalidation against the selected VBR build, target Swagger, product edition, and live account. Pin documentation/API evidence to the build used during implementation; recheck changing sources before deployment.

### 4.1 VBR/API facts to encode and revalidate

- REST API revision 1.3-rev2 was introduced with VBR 13.1. KB4738 identified VBR 13.1.2.57 as the dated recommended Windows build, with repacked ISO media dated 2026-11-06. Use 13.1.2.57 as the initial minimum approved lab build only after revalidation; it is not a permanent assertion that this will always be the latest recommended patch.
- Windows VBR server is the initial live-qualified platform. Linux-appliance account guidance is distinct; Linux live qualification is future/optional and must not be inferred from generic Linux Azure images or a converted appliance.
- `GET /api/v1/configBackup` exposes fields including `isEnabled`, `backupRepositoryId`, `restorePointsToKeep`, `schedule`, `encryption`, and `lastSuccessfulBackup.lastSuccessfulTime/sessionId`. `GET /api/v1/configBackup` requires an administrator according to the checked API documentation.
- `GET /api/v1/securityAnalyzer/bestPractices` returns existing best-practice results (`bestPractice`, `status`, `note`); `/lastRun` reports the existing run. These are observations, not a trigger to run the analyzer. Access requires the relevant administrator/security role; verify exact permissions before implementation.
- Restore points and sessions are different resources. Restore-point evidence includes `creationTime`, `backupId`, and `malwareStatus`; session evidence includes session type, job identifier, end time, and outcome. Verify exact field names against the selected schema. Do not derive one resource's state from the other.
- Repository state fields include `isOnline`, `isOutOfDate`, `capacityGB`, `freeGB`, and `usedSpaceGB`. A repository type such as Linux Hardened is not, on its own, proof of immutability.
- VMware job models expose relevant fields such as storage retention policy type/quantity, `advancedSettings.backupHealth`, `storageData.encryption`, `guestProcessing.appAwareProcessing`, and schedule. Hyper-V and representative Agent schemas must be verified independently against the target version.
- Configuration backup and user/general-option endpoints are administrator-only in the checked material. The Users API includes `mfaEnabled`, `roles`, and `isServiceAccount`; `GET roles`, user-role listing, and role-permission listing are distinct operations with distinct access requirements.
- Additional reader/viewer/custom-role permissions for sessions, restore points, repositories, and other endpoints are endpoint-specific. Build the exact matrix from version-matched docs, target Swagger, and real probes. Do not assume a custom role bypasses an endpoint's admin restriction.
- VBR REST MFA is unsupported for the noninteractive service-account mode. MFA-off applies only to a dedicated VBR service account; do not disable MFA globally. Human MFA requirements must be treated separately. Community Edition limitations (including unsupported MFA) are capability facts, not a passing control.
- VBR MFA does not support user groups. Group-based human access requires an Investigate finding for the unresolved MFA/member evidence, not a passing result or automatic exemption.
- Windows setup guidance is to create a dedicated Windows/domain user, assign the VBR role, and mark it as a VBR service account where required. Linux Host Management Console (HMC) account roles are distinct from VBR roles: an appropriate HMC User can receive a VBR role and VBR service-account flag; HMC Service Account and Security Officer roles cannot receive VBR roles. An HMC Host Admin with VBR access can only receive Backup Administrator and is not the default monitoring identity. Verify exact UI names and steps against the selected build.
- Do not fabricate OAuth/client-credential or managed-identity authentication to VBR. MI applies to Azure operations only; use Key Vault to retrieve specifically approved VBR credentials/secrets.

### 4.2 Maester behavior to verify against the pinned engine

- Native test format consists of a PowerShell test function and companion Markdown file; Pester is for offline unit/fixture testing, not the pack's native test format.
- Permission metadata is descriptive and recorded; it is not enforced by the test engine.
- Native outcomes are `Passed`, `Failed`, `Investigate`, `Error`, `Skipped`, and engine-generated `NotRun`. Only `Passed` counts as compliant; unknown, suppressed, skipped, or not-run states must not be converted into a pass.
- `Add-MtTestResultDetail -Investigate` followed by `return $null` produces `Investigate` in the checked primary docs. Do not claim a seventh `Suppressed` result. A suppression, if supported as a finding disposition, is metadata attached to an Investigate finding, never a pass.
- Explicitly define outcomes on every path: `$true` only for Passed; `$false` for Failed; Investigate flag plus null for uncertain/incomplete evidence; sanitized throw for Error; Skip only for documented genuine non-applicability. Do not leave bare `$null` paths without the appropriate result detail.
- Runtime parameters apply to a single selected test; suite-wide configuration requires the supported configuration overlay object. Verify precedence against the pinned engine: selected-test runtime value, instance/test `TestSettings`, `GlobalSettings`, then defaults.
- Maester's Graph request helper is a reference for paging, caching, bypass, and reset behavior, not evidence of a VBR cache hook. Pin its source before using any analogous design; do not build on a moving `main` branch without a pinned revision.
- Current scaffold CI installs an unpinned Maester prerelease. Leave that workflow unchanged for this documentation-only commit; pin and validate its dependencies during the approved offline implementation phase.

## 5. Baseline policy and control catalog

The default profile must be a documented, recommended baseline with explicit runtime parameters, effective values, units, source, and exceptions. It is not a universal production standard. Declare settings through VBR-prefixed `GlobalSettings` and native-validated parameters; do not invent a parallel configuration engine. Per-test/instance overrides must be bounded and documented. Report baseline version and effective values so an exception is visible and attributable.

Candidate default recommendations, subject to version/edition validation and documented overrides:

- Expected, approved backup jobs run daily. Do not require every job to run daily if an approved schedule is manual, chained, or otherwise intentionally different.
- Standard freshness threshold: 26 hours, consisting of a 24-hour target plus a visible two-hour allowance. This is not a strict 24-hour RPO. Permit explicit strict-24-hour or per-object overrides.
- Minimum retention: 14 days and a minimum of 14 restore points are separate checks; do not treat point count as an equivalent number of days.
- Configuration backup enabled, scheduled daily, with at least 14 restore points and last-success age no greater than 48 hours (explicitly allowing one missed daily cycle).
- Repository free-space thresholds: at least 15% and at least 20 API-reported GB, both required where capacity is meaningful. Do not silently treat API GB as GiB.
- Maximum running-job duration: 12 hours, with an explicit policy outcome for long-running/unknown sessions.
- Session warnings default to Investigate; an operator may choose a stricter Fail policy. Confirmed terminal failures produce Failed after accounting for retries. Missing or ambiguous evidence is Investigate or Error as appropriate, never a silent pass.
- Weekly health checks where applicable; application-aware processing for classified applications, with missing classification reported as Investigate.
- Configuration and job encryption expected enabled. Human MFA expected; service-account MFA exception requires explicit approval, owner, reason, and expiry. No automatic privileged-principal exemption.
- Approved administrator/service-account allowlists default to empty. Empty means policy is unconfigured/unknown and should Investigate, not allow every principal.
- Malware inline detection and signature/IOC updates expected enabled where licensed and prerequisites apply. Guest indexing prerequisites must be represented accurately.
- Notifications for warnings and failures require recipients. TLS syslog is recommended and configurable; settings are not proof of SIEM delivery.
- Security analyzer run age at most seven days. Record findings and suppressions separately; do not let a suppression become a clean result.
- GFS retention is opt-in rather than universal.
- Independent immutable copy with 14 configured immutable days is a recommendation gated on actual API fields and correlated evidence. Never infer immutability from repository type. Do not claim 3-2-1-1-0 assurance.

Proposed parameter names make units and override intent explicit:

| Parameter | Default | Application |
| --- | --- | --- |
| `MaximumRestorePointAgeHours` | 26 | Observed point age; strict profile uses 24. |
| `MinimumRetentionDays` | 14 | Day-based retention only. |
| `MinimumRestorePoints` | 14 | Point-count retention only; not equivalent to days. |
| `MinimumConfigurationBackupRestorePoints` | 14 | Configuration-backup retention. |
| `MaximumConfigurationBackupAgeHours` | 48 | Last successful configuration backup. |
| `MinimumFreeSpacePercent` / `MinimumFreeSpaceGB` | 15 / 20 | Both required for meaningful capacity-reporting repositories. |
| `MaximumRunningSessionHours` | 12 | Per-job duration policy. |
| `WarningHandling` | Investigate | Valid choices Investigate or Fail. |
| `MaximumAnalyzerAgeDays` | 7 | Existing analyzer-run evidence. |
| `MinimumImmutabilityDays` | 14 | Deferred until the exact configuration/correlation contract is verified. |

Document selected-test runtime `-Parameter` examples and full-suite runtime `-Config` objects, plus persistent `TestSettings`/declared `GlobalSettings` examples. Validate all types, units, ranges, precedence, and per-instance overrides against the pinned engine; do not promise an unverified CLI interface.

Planned control groups (specific endpoint, schema, access, and result semantics are Phase B acceptance work):

| Group | Candidate assertions |
| --- | --- |
| Implementation/compatibility | VBR version and minimum approved patch; API availability/revision; infrastructure existence and required visibility; repository online/out-of-date state; license/edition capability. |
| Configuration | Configuration backup enabled, schedule, target and retention; job schedule and retention; GFS where configured; application-aware processing; encryption; backup-health settings; notifications and recipients. |
| Operations | Expected-object inventory; freshness; sessions and latest terminal outcomes; retry/grouping behavior; stuck/running-duration threshold; restore-point evidence; repository capacity/online/out-of-date state; configuration-backup success; analyzer freshness. |
| Security | Configuration/job encryption; human MFA; approved role and service identities; service-account exception owner/expiry; malware mechanisms and prerequisites; signatures/IOCs; approved exclusions with owner/reason/UTC expiry; analyzer findings and suppressions; TLS syslog configuration/filtering. |
| Qualified extensions | Four-eyes approval evidence; per-repository/per-object immutability; copy coverage, failure-domain separation, repair and verification evidence. These must be gated on actual fields and correlations and cannot be claimed from configuration hints alone. |

Inventory must be explicitly declared per site/workload. Never infer coverage from an empty inventory, an `offsite` label, a cloud repository type/name, or a successful query alone. Findings should carry stable object IDs rather than names, measured values, threshold/source, evidence timestamps, principal/profile, scope, workload, category, and evidence type. Unknown schema or incomplete collection is not success. No blanket compliance or recoverability claim.

## 6. Permission model and setup guidance

Create a machine-readable permission catalog linking each test ID and workload to operation ID, HTTP verb/path, documented role, verified custom permission IDs, scope, profile, required visibility evidence, version, and verification status. Generate a human-readable permission matrix from it.

- Operational Reader is the default assessment profile. Security Reader may be used only where its endpoint permissions are verified; its name does not establish read-only access.
- Operational Reader, Security Reader, and Comprehensive Backup Administrator are pack profile labels, not assertions that similarly named VBR roles exist. Map each profile to exact verified built-in roles or custom permission IDs in the catalog.
- Comprehensive Backup Administrator access is explicit opt-in, never an automatic fallback. A read-only HTTP GET does not prove that the assigned account role is read-only.
- A 403 during a required collection is an Error/permission failure, not Investigate or Skipped. A successful but scope-limited query may yield an Investigate coverage finding if visibility cannot be established. Never silently omit checks because the account is underprivileged.
- Use one principal per connection/run. V0.1 does not merge credentials, elevate automatically, or retry under a different identity.
- The main operational tradeoff must be prominent: noninteractive VBR access may require a dedicated account with MFA off. Document restricted network source IPs, private connectivity to VBR port 9419, Key Vault retrieval/rotation, audit, ownership and expiry, and enabling/revoking access where practical. Do not change production accounts automatically.
- The assessment principal cannot approve its own exemption. Exemptions require separately attributable human approval.
- Provide separate setup paths for Windows and Linux appliances: create/configure identity, assign supported role and service-account mode where applicable, document MFA implications and object visibility, use a private CA/trust chain as required, and describe minimal connection/GET smoke checks. Windows setup is to be live-verified; Linux guidance is documentation-verified until its separate live qualification is completed. Include 401/403 interpretation, secret rotation and revocation. Assessment must not require hypervisor administrator credentials.

## 7. REST client and collection design

Proposed service: `VBR.RestApi`. Proposed local connector surface: `Invoke-VbrRestRequest`, `Connect-VbrRest`, `Test-VbrRest`, `Update-VbrConnection` for renewal, `Get-VbrConnectionDescription`, and `Disconnect-VbrRest`, registered through the manifest's native connector lifecycle. Names are proposals pending repository conventions and versioned API review; use approved PowerShell verbs for public functions.

- Require strict HTTPS, hostname and certificate-chain validation; no insecure fallback. Send credentials only to a configured origin, reject user-info URLs and cross-origin redirects, and allowlist API revision, paths, verbs, and query forms. Only GET plus required authentication refresh/logout operations are in scope.
- There is no production mutation mode. Any lab mutation harness must be separate, administrative, and restricted to resources explicitly owned by that run.
- Keep credentials and session tokens in memory. Do not cache authentication responses or log secrets. Implement expiry-aware renewal and at most one refresh/replay on 401; never retry 403 as authentication. Bound GET retry for transient errors and 429 using `Retry-After`, total deadlines, cancellation, and timeouts.
- V0.1 is strictly sequential: no in-flight request deduplication, run-space sharing, or concurrent cache scopes. Reuse of a token within its connection is allowed.
- Follow full VBR pagination. Validate totals, duplicates, forward progress and completeness. Do not publish a partial collection as complete. A server-side filtered GET proves only that filtered view, not global visibility.
- Use typed normalizers. Do not guess null/false/zero values or enum meaning. Unknown schema should produce a controlled error or Investigate according to whether evaluation can safely continue.

### 7.1 Explicit cache contract

Do not cache results unless a pack-owned assessment run/scope is active. Provide a thin `Invoke-VbrAssessment` wrapper around native `Invoke-Maester` that creates a unique scope and resets/disposes it in `finally` on success, failure, and cancellation. Direct `Invoke-Maester` or `Invoke-MtTest` use remains fully supported but uncached unless a verified native run-ID hook becomes available. Do not expose a public `StartCache` API or permit nested/concurrent scopes.

- Key entries by scope ID, connection generation, principal, origin/server identity, API revision, verb, canonical query, response/page and collection shape. Never key by token or include secrets.
- Connect/reconnect, logout, authentication-scope change, or identity change invalidates the scope. A renewal with unchanged identity/scope may retain still-valid entries.
- Provide explicit bypass and clear behavior and sanitized cache telemetry (hit/miss, generation, acquisition time).
- Bound cache to at most 128 entries and 32 MiB of serialized payload accounting. This is not a claim that process heap is bounded to 32 MiB. Bound per-response/page staging; on limit, evict or stream uncached while still completing evaluation—never return arbitrary partial data or a partial pass.
- Proposed TTLs within one assessment: infrastructure 300 seconds; identity/security 60 seconds; volatile capacity, sessions, restore points and events 30 seconds. No disk cache and no stale-on-error behavior. Force fresh collection near policy boundaries.
- Report collection interval and source timestamps; the API is not an atomic snapshot.
- Acceptance must include real native-engine contract coverage for cache hits through the wrapper, successive successful runs, direct uncached invocation, and error/cancellation disposal. Static checks must ensure no implicit cache is active without a scope.

### 7.2 Generic processing and capability normalization

Separate three layers: a workload-agnostic REST transport, versioned schema/collection adapters, and shared capability-based evaluation functions. The REST transport owns authentication, version headers, validated requests, pagination, retry, cancellation, and caching for every allowlisted collection; it must not require or branch on a VMware, Hyper-V, or Agent connection. Generic processing does not mean arbitrary URLs, unrestricted HTTP methods, dynamic code execution, or silently trusting unverified required fields or decision-relevant schema semantics. Harmless additive response fields may be ignored and reported; unknown decision-relevant types, fields, or enum values require explicit validation or uncertainty/error handling.

Adapters may select documented job-family endpoints and map different response shapes into a common protection model. Keep workload-specific property paths and enum mappings inside those adapters, not duplicated across Maester tests. The common model includes stable job/object/repository/session identifiers, workload metadata, scheduling, typed retention, encryption, integrity-check settings, applicable guest/application processing, session outcomes, and restore-point evidence. Server-wide settings, identities, configuration backup, repositories, and analyzer results remain independent of protected-workload type.

For each relevant capability, retain its Supported, Unsupported, or Unknown state separately from its configured value, together with source operation/schema version, access scope, collection time, and evidence completeness. Missing or unreadable data is not a disabled setting or proof that a capability is unsupported. Only documented non-applicability that policy permits may skip a control; an unknown capability, collection failure, or missing policy-required protection must have an explicit uncertainty/error/coverage verdict rather than silently disappearing.

| Protection capability | Shared evaluation rule |
| --- | --- |
| Schedule and enablement | Evaluate the configured schedule against the same approved-job policy, not hypervisor presence. |
| Retention | Preserve days versus restore-point units; apply the same typed thresholds to equivalent evidence. |
| Encryption | Evaluate supported job encryption identically across job families; do not infer historical backup encryption from current settings. |
| Integrity and application processing | Use the same policy where supported and applicable; document family-specific prerequisites or unavailable evidence. |
| Sessions and restore points | Normalize identifiers, timestamps, and outcomes while preserving retry and backup/object correlations. |
| Repository and server posture | Evaluate common resource/settings evidence without requiring any specific protected hypervisor. |

Equivalent normalized evidence and policy must produce equivalent native Maester verdicts for Agent, VMware, and Hyper-V fixtures. The Azure representative job validates this shared path, not a separate lab-only evaluator. Adding an adapter must not change the semantics of existing common checks or imply that every job family exposes identical capabilities. Do not claim live validation of an unexercised schema adapter merely because the common evaluator is live-tested.

## 8. Result semantics and evidence

Translate native outcomes explicitly: boolean true only for Passed, false for Failed, Investigate detail plus null, sanitized exception for Error, Skip only for documented non-applicability, and NotRun only as reported by the engine. A result that cannot be evaluated because expected inventory or permissions are missing must not pass. Keep top-level coverage visible so an object-ID mismatch or a `NoInstances` state cannot hide missing expected objects.

Separate desired policy, observed configuration, recent operational evidence, and live test qualification. Permission metadata is descriptive, not an engine authorization boundary. Check VBR capabilities and edition attributes; do not confuse them with Microsoft license attributes. Redact credentials and sensitive payloads from reports/logs while retaining enough safe provenance to reproduce an assessment.

## 9. Testing and qualification gates

Every pull request should have free, offline checks only. No Azure/VBR live dependency in public CI.

### 9.1 Offline checks

- Run `Test-MtPack` and validate manifest, native test/Markdown pairing, IDs, and documentation structure against the pinned Maester engine.
- Pester unit/contract tests use synthetic fixtures for VMware, Hyper-V, and the representative Agent schema; verify typed normalization, missing/unknown fields, and coverage distinctions. These fixtures are not live evidence.
- Include cross-family equivalence tests: equivalent normalized capabilities and policy produce the same verdicts, thresholds, and evidence requirements for Agent, VMware, and Hyper-V. Test documented Unsupported separately from Unknown and permission failure; prove that common/server-wide checks do not depend on hypervisor presence.
- Test parameter bounds/precedence, configuration overlays, policy thresholds, unit handling, inventory completeness, and explicit six-outcome mapping.
- Test mutation boundary: assessment requests must remain read-only; any lab mutator is isolated and resource-scoped.
- Use a local mock HTTP server/virtual clock for TLS/certificate failures, origins/redirects, 401/403/429, `Retry-After`, paging, token refresh, secret redaction, timeouts/cancellation, unknown enums, stale sessions/jobs, restore-point freshness, capacity units, RBAC visibility, cache isolation, retry bounds, and overrides.
- Test native engine behavior for Investigate and cache-scope disposal. Do not assert that Pester alone proves native pack behavior.
- Reports must retain the coverage profile/workload/API version and evidence type (contract, live API, deployment E2E, or optional restore qualification).

### 9.2 Private live API and deployment E2E

Real API integration and deployment E2E are private Azure-only, manually started or sparsely scheduled, and gated after plan approval and live preflight. They must use a real VBR instance and real endpoint/role probes. The deployment E2E must authenticate to the VBR deployment, create or use the approved representative job (Agent preferred), execute a backup, collect session/restore-point/configuration evidence, and produce a native pack report exercising the Gate B minimum shared core-check set. Capture the profile and checks actually exercised; do not imply complete VMware/Hyper-V live coverage.

Gate B must name the minimum E2E core controls and expected outcomes: job retention, job encryption, session outcome, restore-point freshness, repository capacity, and configuration-backup enablement/encryption/freshness. They must execute rather than be Skipped or NotRun, using the explicitly opted-in lab administrator profile where required. Add representative negative scenarios for supported settings; a proposed job that cannot exercise this minimum set needs a different job/topology or explicit revision and approval of the plan, not silent relaxation.

Probe the Reader, administrator opt-in, and any custom roles separately. Confirm the exact API permissions, object visibility, edition capabilities, and whether each minimum core control is applicable to the selected representative job. Confirm the E2E does not succeed solely through skips. VMware/Hyper-V-specific branches require contract/fixture proof; no genuine VMware lab is required by this plan.

Negative tests may mutate only lab-owned resources and must change one policy dimension at a time (for example, encryption, retention, or schedule), bypass stale cache, and assert the exact expected result. Use virtual time for staleness unit tests; do not fabricate aged live restore points. Optional file-restore/checksum qualification is a separately approved future harness activity, not a v0.1 requirement.

Record installed pack version, lock/version information, native engine version, report, server build, profile, and per-feature coverage privately. Public artifacts must not include live captures, logs, status/results, or identifying environment details without written authorization. Synthetic/documented examples may be published only after redistribution rights are verified.

## 10. Azure lab architecture, cost, and lifecycle

### 10.1 Proposed minimum environment

The preferred representative lab is one Windows VBR 13.1 server and one small Azure VM protected by a VBR-managed Veeam Agent job, plus a small repository target. Another approved Azure-only representative job may replace it under the Gate B capability contract. The selected Windows Server image must be currently supported. VBR server guidance checked for planning listed 6 vCPU and 16 GB RAM; validate against the chosen VBR build and right-size only after preflight. Do not rely on nested virtualization or a fixed Azure VM SKU. A separate repository data disk is preferred; lab-only co-location is permitted only after checking vendor requirements and documenting that it is not production hardening.

Use private connectivity and no broad public management access. Do not require vSphere, AVS, nested ESXi, nested Hyper-V, a hypervisor cluster, or a Veeam Backup for Microsoft Azure product. The latter is not a substitute for actual Windows VBR 13.1 with a VBR-managed Agent. Additional Linux/hardened repository or object-immutability scenarios are later optional work, not v0.1 prerequisites.

### 10.2 Private orchestration and identities

Default to pure Azure private orchestration, not public GitHub Actions. A self-hosted runner for a public repository must never be attached; public CI must have no MI/secret access and must not receive live outputs, checks, callbacks, or status—even if results are passing. Any future public status gate requires separate written consent.

Keep IaC, scripts, and runbooks in this project and deploy a pinned source SHA. An approved existing Azure controller using MI may manually start a run, or a small Azure Automation/Function MI controller may be evaluated. An independent expiry janitor must survive runner failure and be in place before VM creation; a new always-on VM is not presumed necessary. After provisioning and secure bootstrap, SSH is the preferred protocol for guest configuration, script execution, and diagnostics. Azure Run Command or an approved provisioning mechanism may establish SSH initially; subsequent use is a documented bootstrap/recovery exception, not the default steady-state management path. GitHub registration credentials and OIDC are not default requirements.

Separate the Azure controller identity, resource-creation/cleanup identity, Key Vault identity, and VBR assessment identity. MI is not VBR, vCenter, or GitHub authentication. Scope Key Vault access to approved secret retrieval; avoid Owner, broad role-assignment authority, and implicit privilege escalation. Bootstrap role assignments are a separate human-admin action and approval. Do not assume resource-group scope permissions permit deleting the whole group; prefer exact run-owned resource IDs. Do not create a separate private repository without explicit approval.

Define private resource-group/output readers, bootstrap/recovery Run Command log redaction/retention, approved storage identities, and network paths. Avoid public VBR 9419, RDP/SSH, or broad inbound rules. SSH access must be restricted to approved private controller sources; document scoped access rules for the separate VBR and Azure API paths. Run ownership and expiry tags and resource IDs must be recorded without secrets.

The SSH management contract is:

- Use private TCP 22 access restricted to approved controller sources; do not open public SSH, RDP, or WinRM as a convenience. Document and validate controller-to-guest connectivity before choosing the private orchestration runtime.
- For Windows VBR and Windows Agent guests, configure a supported OpenSSH Server and validate the chosen PowerShell-over-SSH or command-execution path. SSH availability is a provisioning/management requirement, not a requirement imposed on production VBR environments by REST-only checks.
- Prefer dedicated, scoped, key-based SSH identities and short-lived per-run access. Verify/pin host keys using an independently trusted bootstrap channel; never disable host-key checking or silently accept unknown keys. Protect private keys in approved ephemeral storage or Key Vault, avoid logs/artifacts, and revoke/remove run-owned access during cleanup.
- Azure managed identity authorizes Azure provisioning, secret retrieval, and resource cleanup; it is not automatically an SSH login. Keep SSH credentials/host trust separate from VBR API credentials and SSH command execution separate from the read-only assessment client's endpoint allowlist.
- VBR assessment continues over HTTPS REST on its configured private endpoint, normally TCP 9419. Azure resource operations continue over Azure management APIs. SSH does not replace either API or authorize additional production operations.
- Bound SSH connection/command duration, output, and cancellation; close task-owned sessions on every exit and redact sensitive diagnostics. Independent Azure-side cleanup must remain possible when SSH or the guest is unavailable.

### 10.3 Assets, preflight, and cleanup

Proposed future layout (not created by this document): offline unit/contract and private integration/E2E fixtures outside pack test suites; Azure Bicep under `lab/azure`; scripts/runbooks under `lab/scripts`. Common workflow responsibilities: provision, seed scenario, assess, collect, cleanup, and cost-check. A nonsecret run manifest should capture exact run ID, owner, expiry, resource IDs, endpoints, media hash, and Key Vault references (not secret values).

Before any spend, require a separately approved maximum-duration (initial recommendation: four hours) and explicit currency budget cap; verify region, quota, current SKU/image pricing, licenses, media, storage, egress, controller/janitor and network costs. No cost quotes are asserted here. Limit to one expensive lab at a time; reuse a run-owned job across serialized scenarios rather than creating one VM per test. Add runtime cost guard and Azure budget alerts, but do not rely on alerts as hard stops because billing data lags. Reconcile actual spend afterward. Spot availability is not a test-gating assumption.

The expiry janitor must be independently scheduled and verified before VM creation. Tag resources with project, run ID, owner, and expiry. In `finally`, attempt cleanup on every outcome; enforce a deadline, then independently verify and remove only that run's VMs, disks, snapshots, network resources, and ephemeral storage. Deallocation does not stop all disk charges. Explicitly budget retained media/cache and document manual stop/cleanup. Do not delete resources belonging to other runs or users.

### 10.4 VBR media, edition, and legal preconditions

Revalidate the download source, recommended patch, ISO hash, supported Windows Server image, edition feature matrix, REST MFA/RBAC constraints, encryption/malware/analyzer/job features, telemetry, licensing, and network/privacy acceptance before deployment. A free Community Edition evaluation may require acceptance of mandatory telemetry, licensing and privacy/network terms. Do not reset trials repeatedly or redistribute VBR media. Choose edition before live qualification; record unavailable edition-dependent features rather than treating them as passes.

The current EULA section 2 evidence checked for planning prohibits third-party disclosure of performance, capacity, functionality, or benchmark results without written consent. This is not a categorical ban on CI. Regardless of anonymization, keep live functionality results, captures, logs, and statuses private unless written permission allows publication. Sanitization alone is not legal permission. Verify current terms and obtain appropriate review before publication.

## 11. Documentation deliverables

After the approval gate, plan to document:

- README implementation status/link, updated only when actual state changes are authorized and evidenced.
- Pack guide and setup: supported VBR/API versions, installation/use, account creation, exact least-privilege profiles, Windows/Linux distinctions, MFA/service-account exception, private network, certificate trust, Key Vault, troubleshooting and revocation.
- Machine-generated permission catalog and human-readable matrix, including profile/version/evidence/verification status.
- Default baseline and every threshold/unit/override, exception handling and what each test does not prove.
- API client behavior, authentication lifecycle, cache scope/TTL/bypass, privacy/redaction and direct native invocation behavior.
- Generic protection-model/adapters, capability availability and evidence mapping, cross-family equivalence, and a clear distinction between workload metadata and actual check requirements.
- Test catalog with native outcomes, applicability, expected inventory, requirements, evidence limitations and coverage level.
- Testing/contributing guidance for offline, private live integration and E2E; release notes and versioned compatibility/coverage claims.
- Azure bootstrap and SSH-first management guidance, Windows OpenSSH prerequisites, key/host-trust handling, private network rules, explicit fallback cases, and the separate HTTPS REST/Azure API paths.
- This plan remains historical approval-gate documentation; update status only with explicit evidence and approval.

Do not alter the existing installation guidance to suggest the connector is available before it exists and has been verified.

## 12. Phased implementation and acceptance gates

### Phase A — plan publication and explicit approval (current)

1. Review this document, publish it through the authorized documentation-only commit/push workflow, and obtain explicit user approval of the committed/pushed plan.
2. Until that approval is received, do not implement code, tests, IaC, scripts, account setup, live tests, or Azure provisioning. The parent may independently review the exact final document and verify changed paths; that is not user approval.
3. If the plan is rejected or materially changed, revise and republish for approval before proceeding. Plan approval is not approval for Azure budget, elevated access, production changes, destructive actions, or a particular spend.

**Gate A evidence:** committed and pushed plan revision plus explicit user approval. Without both, stop.

### Phase B — evidence, compatibility, and permissions contract

After Gate A, pin Maester and VBR/API documentation/evidence; verify target build and schema for VMware, Hyper-V, and the representative job (Agent preferred); verify endpoint permissions by role and scope; verify API pagination, fields, enums, edition availability and restrictions. Establish the feature/license matrix, permission catalog, supported baseline, and accurate coverage contract. Resolve the representative-job topology and prove it can exercise the minimum shared core-check set. No live deployment until its separate preflight is approved.

**Gate B evidence:** version-matched schema/permission/edition matrix, fixture contracts for VMware, Hyper-V, and the selected representative job, a common capability model with cross-family policy-to-evidence mappings, the minimum E2E control set, and a viable representative scenario (Agent preferred). Unverified fields/custom permissions/job capabilities remain explicit blockers or qualified limitations—not asserted facts.

### Phase C — offline foundation, controls, and docs

Implement the connector, collection/normalization, inventory, result mapping, run-scoped cache, baseline/control catalog, and offline test layers as approved. Preserve direct native invocation as uncached. Build setup, permissions, baseline, testing and limitation docs from verified contracts. Run the native pack checks and all applicable offline tests against the pinned engine.

**Gate C evidence:** clean offline validation; explicit six-outcome and cross-family equivalence tests; no hypervisor gate on common checks; no unexplained skipped/unknown coverage; cache contract/cleanup tests; read-only request boundary; no secrets in output; reviewable docs consistent with verified API/engine behavior.

### Phase D — private Azure preflight and representative deployment E2E

Only after separate budget, identity, network, media/license, privacy and cleanup approval: provision the minimal private environment, execute the approved representative job (Agent preferred), and collect a private native report. Verify the E2E's minimum core checks and role/visibility probes. Clean up and reconcile spend. Do not add a VMware live lab as a release requirement. Do not publish live evidence absent written consent.

**Gate D evidence:** approved run manifest/budget; supported build/media verification; private networking and least-scope identities; SSH-first management with verified host trust and Windows support where needed; janitor/cleanup proof independent of SSH availability; real authentication/API role probes; successful representative job/session/restore-point evidence; execution of the Gate B minimum core-control set through the common evaluator; private native report with honest coverage; verified cleanup and cost reconciliation. A backup-only success with all core checks skipped fails this gate.

### Phase E — release qualification

Verify installed pack metadata/version lock and native engine integration. Review the coverage matrix and docs against observed evidence. Obtain required final technical review, address blocking findings, and ensure no live/private artifacts or unsupported claims entered public docs. Release only the supported profile and coverage level actually demonstrated.

**Gate E evidence:** accepted review findings, passing applicable build/pack/offline checks, private live qualification record, release documentation, and verified privacy/terms disposition. No test/build/review result is claimed by this proposed plan.

### Deferred v0.2 candidates

Linux live qualification, optional restore/file-checksum testing, advanced immutable-copy correlation, four-eyes/copy separation, additional repository topologies, and credential merging are out of v0.1 scope unless separately approved. Basic analyzer finding/suppression handling remains core correctness, not deferred.

## 13. Unresolved live prerequisites and decision owners

These are open prerequisites, not completed actions:

1. User approval of the committed and pushed plan before implementation.
2. Final version-matched confirmation of VBR 13.1.2.57 recommendation/current patch, ISO provenance/hash, supported Windows image, and REST 1.3-rev2 schema.
3. Product-edition/license selection and exact capability matrix for Agent jobs, security analyzer, malware mechanisms, encryption, custom RBAC and API MFA limitations.
4. Verified schemas and operations/permissions for the representative job, VMware, and Hyper-V; especially whether the selected Azure-only E2E job exercises every minimum shared core check.
5. Real endpoint-level permission probes for Operational Reader, Security Reader, administrator opt-in and candidate custom roles; confirm object visibility and 403 semantics.
6. Human owner/approver for dedicated VBR service identity, MFA-off exception, expiry, network source restrictions, Key Vault access/rotation and revocation.
7. Azure subscription/region/quota, explicit currency spend cap, current price/image/license/media/storage/network/egress estimates, and billing reconciliation owner.
8. Approved private orchestration/controller and MI scopes, resource deployment/deletion permissions, Key Vault roles, private SSH connectivity, Windows OpenSSH/PowerShell support, key and host-trust bootstrap, bounded recovery fallback, private resource-group/output access, and independent janitor ownership.
9. Private network path to VBR 9419; certificate/CA provisioning; approved egress, DNS, storage and telemetry/privacy policy.
10. Free-edition/NFR eligibility, mandatory telemetry and terms acceptance, privacy review, and current Veeam terms/publication permission.
11. Written consent before any public disclosure of live functionality, performance, capacity, or benchmark evidence; otherwise live output remains private.
12. Exact retention of private run reports/logs/artifacts and approved identities; media and lab resource cleanup plan.

Each prerequisite needs an identified human owner and evidence recorded before the relevant gate. If any is unavailable, narrow the claim or stop that phase; do not manufacture evidence or silently weaken the gate.

## 14. Source references

Use version-matched documentation and the selected target's Swagger/API contract. Links below are reference entry points; page content may move or change. Recheck before implementation and record the date/version actually relied upon.

### Veeam VBR REST API and product guidance

- [VBR REST API 1.3-rev2 overview](https://helpcenter.veeam.com/references/vbr/13/rest/1.3-rev2/tag/SectionOverview)
- [Configuration backup](https://helpcenter.veeam.com/references/vbr/13/rest/1.3-rev2/tag/Configuration-Backup)
- [Jobs](https://helpcenter.veeam.com/references/vbr/13/rest/1.3-rev2/tag/Jobs)
- [Repositories](https://helpcenter.veeam.com/references/vbr/13/rest/1.3-rev2/tag/Repositories)
- [Sessions](https://helpcenter.veeam.com/references/vbr/13/rest/1.3-rev2/tag/Sessions)
- [Restore points](https://helpcenter.veeam.com/references/vbr/13/rest/1.3-rev2/tag/Restore-Points)
- [Users and roles](https://helpcenter.veeam.com/references/vbr/13/rest/1.3-rev2/tag/Users-and-Roles)
- [Security](https://helpcenter.veeam.com/references/vbr/13/rest/1.3-rev2/tag/Security)
- [Malware detection](https://helpcenter.veeam.com/references/vbr/13/rest/1.3-rev2/tag/Malware-Detection)
- [General options](https://helpcenter.veeam.com/references/vbr/13/rest/1.3-rev2/tag/General-Options)
- [Veeam Agent management](https://helpcenter.veeam.com/references/vbr/13/rest/1.3-rev2/tag/SectionHowTo#section/Veeam-Agent-Management)
- [VBR 13.1.2.57 patch information, KB4738](https://www.veeam.com/kb4738)
- [MFA](https://helpcenter.veeam.com/docs/vbr/userguide/mfa.html?ver=13)
- [Configure roles](https://helpcenter.veeam.com/docs/vbr/userguide/configure_roles.html?ver=13)
- [RBAC limitations](https://helpcenter.veeam.com/docs/vbr/userguide/rbac_limitations.html?ver=13)
- [Host Management Console users](https://helpcenter.veeam.com/docs/vbr/userguide/hmc_configure_users.html?ver=13)
- [Backup server system requirements](https://helpcenter.veeam.com/docs/vbr/userguide/system_requirements_backup_server.html?ver=13)
- [Install VBR](https://helpcenter.veeam.com/docs/vbr/userguide/install_vbr.html?ver=13)
- [Veeam EULA](https://www.veeam.com/legal/eula.html)
- [Veeam licensing policy](https://www.veeam.com/legal/licensing-policy.html)
- [Veeam security best practices](https://bp.veeam.com/security/) (community guidance, not an R&D product contract)

### Maester

- [Writing a pack](https://maester.dev/docs/packs/writing-a-pack)
- [Writing tests](https://maester.dev/docs/writing-tests)
- [Applicability configuration](https://maester.dev/docs/configuration/applicability)
- [Invoke-MtGraphRequest](https://maester.dev/docs/commands/Invoke-MtGraphRequest) (behavioral reference only; not a VBR cache API)
- [Invoke-MtGraphRequest source on moving main](https://raw.githubusercontent.com/maester365/maester/main/powershell/public/services/graph/Invoke-MtGraphRequest.ps1) (pin a commit before relying on implementation details)

### Azure security, lifecycle, and cost

- [Azure RBAC scope](https://learn.microsoft.com/en-us/azure/role-based-access-control/scope-overview)
- [Delete a resource group](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/delete-resource-group)
- [Key Vault RBAC guide](https://learn.microsoft.com/en-us/azure/key-vault/general/rbac-guide)
- [Virtual machine states and billing](https://learn.microsoft.com/en-us/azure/virtual-machines/states-billing)
- [Create Azure cost budgets](https://learn.microsoft.com/en-us/azure/cost-management-billing/costs/tutorial-acm-create-budgets)
- [Windows OpenSSH installation and first use](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse) (validate against the selected Windows image before implementation)
- [PowerShell remoting over SSH](https://learn.microsoft.com/en-us/powershell/scripting/security/remoting/ssh-remoting-in-powershell) (management transport, not VBR REST authentication)

## 15. Current activity record

The original proposed plan was committed and pushed as `f433d65`, following an Opus PASS and documentation-only checks for changed-path scope, relative links, balanced code fences, final newlines, required decision/approval text, and Git whitespace validation. Those original checks do not establish validation of later revisions.

On 2026-11-26, the clarification of generic capability-based API processing, equal common-capability scope across Agent/VMware/Hyper-V, and SSH-first Azure guest management received an Opus PASS with wording clarifications incorporated. Documentation-only checks passed for the single-file staged scope, relative links, balanced fences/final newline, clarification and approval clauses, and Git whitespace validation. No implementation, provisioning, product tests, build, live API probe, cost validation, or user approval is claimed. The revised plan must be committed, pushed, and explicitly approved by the user before implementation.
