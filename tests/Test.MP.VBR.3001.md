Requires explicit expected job **and** protected-object IDs. Correlates backup `jobId` to point `backupId`, then compares point `backupObjectId` and offset-aware `creationTime` per expected object against the 26-hour default. Unknown links or missing objects Investigate, never pass. Does not prove restore success or full inventory coverage beyond declarations.

#### Remediation action

Verify object/backup correlation and visibility; investigate missing or stale points and run an approved backup.

<!--- Results --->
%TestResult%
