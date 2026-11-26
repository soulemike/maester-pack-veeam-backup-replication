# Baseline and overrides

Baseline `VBR.v0.1` is a recommendation, not proof of recoverability or compliance. Only Passed counts as compliant; Error, Investigate, Skipped and NotRun do not.

| Setting (`VBR.` prefix) | Default | Meaning |
| --- | --- | --- |
| MinimumServerBuild | 13.1.2.57 | Dated four-part minimum; revalidate patch guidance. |
| MinimumRetentionDays | 14 | Day-based retention only. |
| MinimumRestorePoints | 14 | Point-count retention only; not equivalent to days. |
| MinimumConfigurationBackupRestorePoints | 14 | Configuration-backup points. |
| MaximumRestorePointAgeHours | 26 | 24-hour target plus explicit two-hour allowance; not strict 24-hour RPO. |
| MaximumConfigurationBackupAgeHours | 48 | Allows one missed daily cycle. |
| MaximumRunningSessionHours | 12 | Running backup session threshold. |
| MinimumFreeSpacePercent / MinimumFreeSpaceGB | 15 / 20 | Both required; API GB, not GiB. |
| WarningHandling | Investigate | Investigate or Fail; no silent warning pass. |

Native parameter ranges are enforced. The pinned engine supports integer policy settings; fractional hour/GB overrides are not exposed by this milestone.

Explicit `ExpectedJobIds`, `ExpectedRepositoryIds`, and `ExpectedProtectedObjectIds` establish the declared assessment scope. Empty inventory is Investigate, not “everything protected.” `ClassifiedApplicationJobIds` identifies application-bearing jobs; absent classification is unresolved. Unknown job families/properties/enums do not become disabled settings or passes.

```powershell
# Entire selected pack: native configuration overlay
Invoke-Maester -Pack VBR -SkipBuiltIn -Config @{
    GlobalSettings = @{
        'VBR.ExpectedJobIds' = @('11111111-1111-1111-1111-111111111111')
        'VBR.MaximumRestorePointAgeHours' = 24
    }
}

# One selected test: native runtime parameter overrides GlobalSettings
Invoke-MtTest -Id MP.VBR.3001 -Parameter @{ MaximumRestorePointAgeHours = 24 }
```

Precedence is selected-test runtime parameter, native instance/test TestSettings, GlobalSettings, then test default. The native integration suite verifies GlobalSettings and runtime precedence. Persist configuration with Maester's documented TestSettings/GlobalSettings format, not a parallel pack policy engine.

Current limits: health-check control 2013 evaluates enablement only, not weekly frequency. Scope 2012 to daily-required jobs via test-specific ExpectedJobIds; do not apply its daily requirement indiscriminately to approved manual/chained jobs. Encryption checks observe current configuration, not historical backup-file encryption. Restore freshness uses object-scoped reads and backup/job correlations, not the latest job timestamp; incomplete correlations Investigate. This does not prove every undeclared job/object or restore success.
