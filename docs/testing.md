# Validation and qualification

Public CI is synthetic/offline only. It has no Azure identity, VBR secret, live capture, or live status callback. Dependency downloads are pinned in `qa/versions.json`; they are not live product assessments.

```powershell
. ./qa/Initialize-Tools.ps1
Initialize-VbrOfflineTools
. ./qa/Invoke-Offline.ps1
. ./qa/Native.ps1
$result = Invoke-VbrOfflineValidation
Invoke-VbrNativeValidation -Bundle $result.Bundle
```

Downloaded modules, synthetic installed-pack stores, locks/configs and reports remain under ignored `.tools/` within this project. `New-VbrValidationBundle` copies only distributable files: `Test-MtPack` scans every file and must not scan local downloaded module trees as pack content.

Pester checks typed normalization and cross-family equivalence, explicit inventory, thresholds/time offsets, correlation/retries, request safety, pagination/completeness, response bounds/cancellation, cache mutation/isolation and endpoint/adapter extensibility. Native validation locally installs the same bundle and verifies all six outcomes, native configuration/runtime precedence, wrapper cache sharing, independent successive assessments, direct uncached calls, and synthetic-secret absence in checked reports/connection metadata. This is not TLS interoperability, full-stream credential-redaction, or live RBAC qualification.

The engine flags direct .NET networking as High risk and adapter dispatch as dynamic code. These findings are expected and must be reviewed, not suppressed: this is trusted PowerShell code, not a sandbox. Review the configured origin, authentication boundaries and every shipped adapter before installing. Connector password login, reader smoke, renewal and logout have not yet been exercised as a lifecycle. The self-signed TLS negative test lacks a positive handshake control and does not independently prove correct TLS interoperability.

## Remaining live gates

No Azure resource may be provisioned before the next explicit approval. First resolve budget, identity scope, networking/SSH bootstrap, independent expiry janitor, installer/hash, edition/license/privacy and private evidence access/retention. Then private Azure E2E must exercise a representative core-capable VBR job (Agent preferred) through production collection/evaluation; a hypervisor lab is not required.

Minimum live set: applicable job retention, job encryption, terminal session result, object restore-point freshness, repository capacity, configuration-backup enablement/encryption/freshness. Collect actual Reader/admin/custom-role visibility evidence. No control skipping may substitute for the minimum live coverage contract. Keep live results private; sanitization alone does not satisfy Veeam disclosure terms. The present milestone is not Gate B/C/D completion or a release qualification.
