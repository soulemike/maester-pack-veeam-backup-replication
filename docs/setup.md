# Setup (offline milestone; live qualification pending)

Target VBR 13.1 / REST `1.3-rev2`. Offline validation pins Maester `3.0.0-rc83`; Maester 3 remains prerelease. Revalidate the dated minimum build `13.1.2.57`, installer hash, edition features and current license terms before deployment. No VBR or Azure deployment has been performed.

## Assessment identity

1. Create a dedicated Windows/domain identity under your approved identity-management process.
2. In VBR Users and Roles, assign **Backup Viewer** for the default OperationalReader pack profile. Verify actual object visibility and read permissions before relying on results.
3. Configure VBR service-account mode where required for noninteractive REST authentication. REST MFA is unsupported: disable MFA only for this specifically approved service account, never for human access globally.
4. Administrator-only evidence requires the ComprehensiveAdministrator profile, backed by **Backup Administrator**, with explicit `AllowAdministrator` opt-in. This account can modify VBR even though assessment requests are GET-only. Limit it to approved execution windows where practical, restrict network sources, rotate credentials, audit use, and require externally approved ownership/reason/expiry for its MFA exception.
5. Keep credentials in an approved secret manager, such as scoped Azure Key Vault retrieval. Pass a `PSCredential` in memory; do not embed passwords in configuration, command history, reports, or fixtures.

Profile names belong to the pack, not VBR RBAC. [The generated matrix](permissions.md) separates read operations from privileged roles. No custom permission ID is currently live-verified. Reader-mode administrator checks Investigate without sending a request; an actual required GET returning 403 is Error. No automatic elevation or fallback occurs.

Linux-appliance guidance is documentation-only: HMC account roles differ from VBR roles. An appropriate HMC User can receive the VBR role/service-account flag; HMC Service Account and Security Officer roles cannot receive VBR roles. Host Admin with VBR access is not the default monitoring identity. Verify exact supported steps against the selected appliance before use; Linux live qualification is deferred.

## Network and connection

Use an approved HTTPS origin, normally `https://vbr.example.net:9419`, with no path, embedded credentials, query or fragment. The OS must trust the certificate chain and hostname. Install an approved private CA through the normal system trust process; there is no certificate-validation bypass, redirect following, or proxy fallback.

Declare `VBR.Server` in Maester GlobalSettings or supply it in the pinned engine's `ServiceSetting` parameter. The native parameter shape was checked against rc83; the actual VBR login lifecycle remains unqualified. After operator approval of the live assessment environment:

```powershell
$credential = Get-Credential # Or construct PSCredential from approved secret retrieval.
Connect-Maester -Service VBR.RestApi -ServiceSetting @{
    Server = 'https://vbr.example.net:9419'
    Credential = $credential
    Profile = 'OperationalReader'
}

# Only when administrator access is separately approved:
Connect-Maester -Service VBR.RestApi -ServiceSetting @{
    Server = 'https://vbr.example.net:9419'
    Credential = $credential
    Profile = 'ComprehensiveAdministrator'
    AllowAdministrator = $true
}
```

No password belongs in persistent GlobalSettings. The default reader smoke test reads jobs rather than administrator-only server information. `ServiceSetting` can also be keyed by `VBR.RestApi` when several services are specified; it overrides persistent connection settings.

Disconnect with `Disconnect-Maester -Service VBR.RestApi`. Logout is bounded/best effort; local tokens and the HTTP client are disposed even if the server is unavailable. A 401 permits one refresh/replay per logical read; 403 never causes an authentication retry. A failed renewal requires operator reconnection, not automatic password fallback.

## Future Azure lab — approval required

Azure managed identity is for Azure APIs and approved secret retrieval, not VBR OAuth or automatic SSH login. After separately approved provisioning, prefer private SSH guest management, supported Windows OpenSSH, key-based scoped identities, independently verified host keys, and bounded commands. Run Command is bootstrap/recovery only. Assessment remains private HTTPS REST; cleanup uses Azure APIs independently of SSH.

Before any provision: approve region, quota, explicit currency cap, maximum runtime (initial recommendation four hours), media/license/privacy, identity scopes, private networking, private artifact readers, and an independently verified expiry janitor. Do not create resources, assign roles, open ports, or change production accounts based on these instructions alone.
