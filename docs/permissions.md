# Permission matrix

Generated from `catalog/permissions.json` and `catalog/endpoints.json`. Public schema verification is not a live RBAC probe. Custom permission IDs and edition/visibility behavior remain unverified.

All assessment operations below are GET reads. Backup Administrator is nevertheless a privileged, writable account role. Its use requires explicit opt-in; a GET-only pack does not make that account read-only.

| Test | Profile | GET operations | Required visibility |
| --- | --- | --- | --- |
| MP.VBR.1001 | ComprehensiveAdministrator | GetServerInfo (`/api/v1/serverInfo`) | Configured VBR origin; installation ID/build |
| MP.VBR.1002 | OperationalReader | GetAllRepositoriesStates (`/api/v1/backupInfrastructure/repositories/states`) | Explicit ExpectedRepositoryIds |
| MP.VBR.2001 | ComprehensiveAdministrator | GetConfigBackupOptions (`/api/v1/configBackup`) | Server configuration backup |
| MP.VBR.2002 | ComprehensiveAdministrator | GetConfigBackupOptions (`/api/v1/configBackup`) | Server configuration backup |
| MP.VBR.2003 | ComprehensiveAdministrator | GetConfigBackupOptions (`/api/v1/configBackup`) | Server configuration backup |
| MP.VBR.2010 | OperationalReader | GetAllJobs (`/api/v1/jobs`)<br>GetJob (`/api/v1/jobs/{id}`) | Explicit ExpectedJobIds; typed day-based retention |
| MP.VBR.2011 | OperationalReader | GetAllJobs (`/api/v1/jobs`)<br>GetJob (`/api/v1/jobs/{id}`) | Explicit ExpectedJobIds; typed point-count retention |
| MP.VBR.2012 | OperationalReader | GetAllJobs (`/api/v1/jobs`)<br>GetJob (`/api/v1/jobs/{id}`) | Explicit ExpectedJobIds; approved daily job scope |
| MP.VBR.2013 | OperationalReader | GetAllJobs (`/api/v1/jobs`)<br>GetJob (`/api/v1/jobs/{id}`) | Explicit ExpectedJobIds; health-check enablement only |
| MP.VBR.3001 | OperationalReader | GetAllJobs (`/api/v1/jobs`)<br>GetJob (`/api/v1/jobs/{id}`)<br>GetAllBackups (`/api/v1/backups`)<br>GetBackupObjectRestorePointsWithFiltering (`/api/v1/backupObjects/{id}/restorePoints`) | Explicit ExpectedJobIds and ExpectedProtectedObjectIds; object-scoped points correlated through backupId/jobId |
| MP.VBR.3002 | OperationalReader | GetAllJobs (`/api/v1/jobs`)<br>GetJob (`/api/v1/jobs/{id}`)<br>GetAllSessions (`/api/v1/sessions`) | Explicit ExpectedJobIds; latest unambiguous backup session/retry chain |
| MP.VBR.3003 | OperationalReader | GetAllJobs (`/api/v1/jobs`)<br>GetJob (`/api/v1/jobs/{id}`)<br>GetAllSessions (`/api/v1/sessions`) | Explicit ExpectedJobIds; running backup sessions |
| MP.VBR.3004 | OperationalReader | GetAllRepositoriesStates (`/api/v1/backupInfrastructure/repositories/states`) | Explicit ExpectedRepositoryIds; meaningful API capacity |
| MP.VBR.3005 | ComprehensiveAdministrator | GetConfigBackupOptions (`/api/v1/configBackup`) | Last successful configuration backup timestamp |
| MP.VBR.4001 | ComprehensiveAdministrator | GetConfigBackupOptions (`/api/v1/configBackup`) | Configuration backup encryption setting |
| MP.VBR.4010 | OperationalReader | GetAllJobs (`/api/v1/jobs`)<br>GetJob (`/api/v1/jobs/{id}`) | Explicit ExpectedJobIds; current job encryption setting |
| MP.VBR.4011 | OperationalReader | GetAllJobs (`/api/v1/jobs`)<br>GetJob (`/api/v1/jobs/{id}`) | Explicit ExpectedJobIds and ClassifiedApplicationJobIds |

OperationalReader maps to documented Backup Viewer access for these common reads. ComprehensiveAdministrator maps to Backup Administrator. These are pack profile labels. Neither profile nor permission metadata is a substitute for live object-visibility verification.

Reader mode does not send administrator-only requests: those controls return Investigate. An actual required GET returning 403 is Error. No role fallback, credential merging, or privilege elevation occurs.
