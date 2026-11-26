# Veeam Backup & Replication Checks

Assesses VBR implementation, configuration, operations, and security through its REST API. Agent, VMware, and Hyper-V share the same common-capability checks; a hypervisor connection is not required.

## Local milestone validation

Run the [offline validation commands](docs/testing.md), then install the generated clean bundle locally for assessment evaluation. Repository-source installation and release qualification remain unverified; do not assume the public repository already publishes this working tree.

```powershell
Install-MtPack -Source '<approved-clean-bundle-folder>'
Connect-Maester -Service VBR.RestApi
Invoke-Maester -Pack VBR -SkipBuiltIn
```

This is a [Maester Pack](https://maester.dev/docs/packs). Its page is [packs.maester.cloud/p/vbr](https://packs.maester.cloud/p/vbr).

## Implementation status

The [implementation plan](docs/implementation-plan.md), revision `3a1bc37`, was explicitly approved on 2026-11-26. Offline implementation is underway; **Azure provisioning requires the next explicit approval**.

The first milestone supplies a GET-only transport, endpoint/adaptor extension contracts, scoped cache, and 17 native controls. It is not a completed release or live-qualified production assessment. [Current status and remaining work](docs/implementation-status.md).

- [Account setup and security tradeoffs](docs/setup.md)
- [Per-test permission matrix](docs/permissions.md)
- [Defaults and runtime overrides](docs/baseline.md)
- [Transport and endpoint extensions](docs/api-client.md)
- [Offline validation and live gates](docs/testing.md)

**Important:** the default reader profile does not elevate. Administrator-only checks require explicit opt-in, and noninteractive REST access may require a dedicated VBR service account with MFA disabled for that account only. Never disable human MFA globally. No Azure managed identity or Microsoft Graph credential authenticates to VBR.
