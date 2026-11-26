function Invoke-VbrTransportTests {
Describe 'Transport contracts' {
BeforeAll {
    Add-Type -Path "$PSScriptRoot/../MockHttp.cs"
    $script:root = [IO.Path]::GetFullPath("$PSScriptRoot/../..")
    function New-TestPack {
        $module = New-Module -Name VbrOfflineTransport -ScriptBlock {
            param($root)
            . "$root/helpers/00.Foundation.ps1"
            . "$root/helpers/10.Transport.ps1"
            . "$root/connectors/Vbr.ps1"
            function Set-MtConnectionState { param($Service,$Value,$Account,$Tenant) $script:state = $Value }
            function Get-MtConnectionState { param($Service) $script:state }
            function Clear-MtConnectionState { param($Service) $script:state = $null }
            function Invoke-Maester { param($Pack,$SkipBuiltIn,$TestId,$NonInteractive,$DisableTelemetry,$SkipVersionCheck,$PassThru,$Config,$OutputFolder) & $script:action }
            Initialize-VbrCatalog
            $script:handler = [VbrMockHttpHandler]::new()
            $script:VbrSession = @{ Origin = [uri]'https://vbr.example.net:9419'; Client = [Net.Http.HttpClient]::new($script:handler)
                Principal = 'synthetic-reader'; Profile = 'OperationalReader'; Generation = [guid]::NewGuid().ToString()
                ServerIdentity = 'synthetic-server'; AccessToken = 'SENTINEL_ACCESS'; RefreshToken = 'SENTINEL_REFRESH'
                ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Busy = $false }
            # New-Module otherwise imports its exports into the caller and can
            # shadow the real Maester commands used by later native validation.
            Export-ModuleMember -Function @() -Variable @() -Alias @()
        } -ArgumentList $root
        return $module
    }
    function New-CollectionJson([string[]]$Ids, [int]$Total, [int]$Skip = 0) {
        $data = @($Ids | ForEach-Object { @{ id = $_; type = 'VSphereBackup' } })
        ConvertTo-Json -InputObject @{ data = $data; pagination = @{ total = $Total; count = $data.Count; skip = $Skip; limit = 200 } } -Compress -Depth 5
    }
    $script:id1 = '11111111-1111-1111-1111-111111111111'
    $script:id2 = '22222222-2222-2222-2222-222222222222'
}
BeforeEach { $script:pack = New-TestPack }
AfterEach {
    & $pack { if ($script:VbrSession) { $script:VbrSession.Client.Dispose() }; Clear-VbrCache; $script:VbrScope = $null }
    Remove-Module $pack -ErrorAction SilentlyContinue
}

Describe 'Declarative transport safety' {
    It 'rejects unknown operations, invalid path parameters, and administrator collection before HTTP' {
        & $pack {
            { Invoke-VbrRestRequest Unknown } | Should -Throw 'VBR.UnregisteredOperation'
            { Invoke-VbrRestRequest GetJob @{ id = '../oauth2/token' } } | Should -Throw 'VBR.InvalidParameter'
            { Invoke-VbrRestRequest GetJob @{ id = '11111111-1111-1111-1111-111111111111'; injected = 1 } } | Should -Throw 'VBR.InvalidParameter'
            { Invoke-VbrRestRequest GetServerInfo } | Should -Throw 'VBR.AdminProfileRequired'
            $script:handler.Requests.Count | Should -Be 0
        }
    }
    It 'follows server-capped pages by actual count and validates the total' {
        $page1 = New-CollectionJson @($id1) 2
        $page2 = New-CollectionJson @($id2) 2 1
        & $pack { param($a,$b)
            $script:handler.Enqueue(200,$a); $script:handler.Enqueue(200,$b)
            $r = Invoke-VbrRestRequest GetAllJobs
            $r.Data.Count | Should -Be 2
            $r.Complete | Should -BeTrue
            $script:handler.Requests[1] | Should -Be 'GET /api/v1/jobs?limit=200&skip=1'
        } $page1 $page2
    }
    It 'rejects duplicate IDs and changing/empty incomplete pages without returning a partial collection' {
        $page = New-CollectionJson @($id1) 2
        $duplicate = New-CollectionJson @($id1) 2 1
        & $pack { param($a,$b)
            $script:handler.Enqueue(200,$a); $script:handler.Enqueue(200,$b)
            { Invoke-VbrRestRequest GetAllJobs } | Should -Throw 'VBR.DuplicateIdentity'
        } $page $duplicate
        $changed = New-CollectionJson @($id2) 3 1
        $empty = New-CollectionJson @() 2 1
        & $pack { param($a,$changed,$empty)
            $script:handler.Enqueue(200,$a); $script:handler.Enqueue(200,$changed)
            { Invoke-VbrRestRequest GetAllJobs } | Should -Throw 'VBR.ChangingCollection'
            $script:handler.Enqueue(200,$a); $script:handler.Enqueue(200,$empty)
            { Invoke-VbrRestRequest GetAllJobs } | Should -Throw 'VBR.IncompletePagination'
        } $page $changed $empty
    }
    It 'accepts the schema jobIdFilter query and rejects an invented jobId query' {
        & $pack {
            { Invoke-VbrRestRequest GetAllSessions @{ jobId = '11111111-1111-1111-1111-111111111111' } } | Should -Throw 'VBR.InvalidParameter'
            $script:handler.Enqueue(200,'{"data":[],"pagination":{"count":0,"total":0}}')
            $null = Invoke-VbrRestRequest GetAllSessions @{ jobIdFilter = '11111111-1111-1111-1111-111111111111' }
            $script:handler.Requests[0] | Should -Be 'GET /api/v1/sessions?jobIdFilter=11111111-1111-1111-1111-111111111111&limit=200&skip=0'
        }
    }
    It 'does not retry 403 or follow redirects, and never surfaces the error body' {
        & $pack {
            $script:handler.Enqueue(403,'SENTINEL_PASSWORD'); $script:handler.Enqueue(302,'SENTINEL_PASSWORD')
            { Invoke-VbrRestRequest GetAllJobs } | Should -Throw 'VBR.PermissionDenied'
            { Invoke-VbrRestRequest GetAllJobs } | Should -Throw 'VBR.HttpStatus.302'
            $script:handler.Requests.Count | Should -Be 2
        }
    }
    It 'refreshes once per logical paged request and stops a second 401' {
        & $pack {
            $script:handler.Enqueue(401,'')
            $script:handler.Enqueue(200,'{"access_token":"SENTINEL_NEW","refresh_token":"SENTINEL_ROTATED","token_type":"bearer","expires_in":900}')
            $script:handler.Enqueue(401,'')
            { Invoke-VbrRestRequest GetAllJobs } | Should -Throw 'VBR.HttpStatus.401'
            @($script:handler.Requests | Where-Object { $_ -like 'POST*' }).Count | Should -Be 1
        }
    }
    It 'honors cancellation and rejects oversized response staging' {
        & $pack {
            $cancel = [Threading.CancellationTokenSource]::new(); $cancel.Cancel()
            try { { Invoke-VbrRestRequest GetAllJobs -CancellationToken $cancel.Token } | Should -Throw 'VBR.RequestFailed' }
            finally { $cancel.Dispose() }
            $script:handler.Requests.Count | Should -Be 0
            $script:handler.Enqueue(200,('x' * 4194305))
            { Invoke-VbrRestRequest GetAllJobs } | Should -Throw 'VBR.ResponseLimit'
        }
    }
    It 'keeps timestamps as strings and rejects duplicate JSON fields' {
        & $pack {
            (ConvertFrom-VbrJson '{"time":"2026-11-26T12:00:00+01:00"}').time | Should -BeOfType [string]
            { ConvertFrom-VbrJson '{"id":1,"id":2}' } | Should -Throw 'VBR.InvalidJson'
        }
    }
    It 'rejects an untrusted TLS server using the production certificate policy' {
        & $pack {
            $server = [VbrUntrustedTlsServer]::new()
            $handler = [Net.Http.HttpClientHandler]::new(); $handler.AllowAutoRedirect = $false; $handler.UseProxy = $false
            $client = [Net.Http.HttpClient]::new($handler)
            $session = @{ Origin = [uri]"https://localhost:$($server.Port)"; Client = $client; AccessToken = 'SENTINEL_ACCESS' }
            $deadline = [Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds(5))
            try { { Invoke-VbrHttp $session ([uri]::new($session.Origin,'/api/v1/jobs')) GET $null $deadline.Token } | Should -Throw 'VBR.TransportFailure' }
            finally { $deadline.Dispose(); $client.Dispose(); $server.Dispose() }
        }
    }
    It 'bounds retry count and Retry-After by the logical deadline' {
        & $pack {
            1..3 | ForEach-Object { $script:handler.Enqueue(503,'') }
            { Invoke-VbrRestRequest GetAllJobs } | Should -Throw 'VBR.HttpStatus.503'
            $script:handler.Requests.Count | Should -Be 3
            $script:handler.Enqueue(429,'',10)
            { Invoke-VbrRestRequest GetAllJobs -TimeoutSeconds 1 } | Should -Throw 'VBR.RetryDeadlineExceeded'
        }
    }
}

Describe 'Assessment cache isolation' {
    It 'copies cached evidence, bypasses explicitly, and leaves direct calls uncached after a wrapper run' {
        $page = New-CollectionJson @($id1) 1
        & $pack { param($json)
            1..3 | ForEach-Object { $script:handler.Enqueue(200,$json) }
            $script:action = {
                $a = Invoke-VbrRestRequest GetAllJobs
                $a.Data[0].type = 'mutated'
                $b = Invoke-VbrRestRequest GetAllJobs
                $b.CacheHit | Should -BeTrue
                $b.Data[0].type | Should -Be 'VSphereBackup'
                (Invoke-VbrRestRequest GetAllJobs -BypassCache).CacheHit | Should -BeFalse
            }
            Invoke-VbrScopedAssessment
            $script:VbrScope | Should -BeNullOrEmpty
            (Invoke-VbrRestRequest GetAllJobs).CacheHit | Should -BeFalse
            $script:handler.Requests.Count | Should -Be 3
        } $page
    }
    It 'disposes a failing scope and rejects nested assessment' {
        & $pack {
            $script:action = { Invoke-VbrScopedAssessment }
            { Invoke-VbrScopedAssessment } | Should -Throw 'VBR.NestedAssessmentUnsupported'
            $script:VbrScope | Should -BeNullOrEmpty
        }
    }
    It 'extends an endpoint and adapter without changing the handler and isolates operation/path identities' {
        $page = New-CollectionJson @($id1) 1
        & $pack { param($json)
            # This registration exists only in the private offline test module, not a shipped hook.
            function ConvertFrom-VbrFutureCollection { param($Payload,$Definition,$Offset) ConvertFrom-VbrSkipLimit $Payload $Definition $Offset }
            $def = ConvertFrom-VbrJson ($script:VbrOperations.GetAllJobs | ConvertTo-Json -Depth 8)
            $def.Id = 'FutureRead'; $def.Path = '/api/v1/future'; $def.Adapter = 'FutureCollection'
            $script:VbrOperations.FutureRead = $def
            $script:VbrAdapterCommands.FutureRead = @{ Request = $script:VbrAdapterCommands.GetAllJobs.Request; Response = (Get-Command ConvertFrom-VbrFutureCollection) }
            $before = (Get-Command Invoke-VbrRestRequest).ScriptBlock.ToString()
            $script:handler.Enqueue(200,$json); $script:handler.Enqueue(200,$json)
            $script:action = {
                (Invoke-VbrRestRequest GetAllJobs).CacheHit | Should -BeFalse
                (Invoke-VbrRestRequest FutureRead).CacheHit | Should -BeFalse
                (Invoke-VbrRestRequest FutureRead).CacheHit | Should -BeTrue
            }
            Invoke-VbrScopedAssessment
            $script:handler.Requests[1] | Should -Be 'GET /api/v1/future?limit=200&skip=0'
            (Get-Command Invoke-VbrRestRequest).ScriptBlock.ToString() | Should -Be $before
        } $page
    }
    It 'supports a new cursor pagination convention through adapters, without handler edits' {
        & $pack {
            function Get-VbrFutureCursorParameters {
                param($Parameters,$PageState)
                $p = @{} + $Parameters
                if ($PageState) { $p.cursor = [string]$PageState }
                $p
            }
            function ConvertFrom-VbrFutureCursor {
                param($Payload,$Definition,$PageState)
                @{ Data = $Payload.data; Total = $Payload.total; Done = ($null -eq $Payload.next); NextState = $Payload.next }
            }
            $def = ConvertFrom-VbrJson ($script:VbrOperations.GetAllJobs | ConvertTo-Json -Depth 8)
            $def.Id = 'FutureCursor'; $def.Path = '/api/v1/cursor'
            $def.Adapter = 'FutureCursor'; $def.RequestAdapter = 'FutureCursor'
            $def.Parameters = @{ cursor = @{ Type = 'String'; Location = 'Query'; Pattern = '^c[0-9]+$'; MaximumLength = 32 } }
            $script:VbrOperations.FutureCursor = $def
            $script:VbrAdapterCommands.FutureCursor = @{ Request = (Get-Command Get-VbrFutureCursorParameters); Response = (Get-Command ConvertFrom-VbrFutureCursor) }
            $before = (Get-Command Invoke-VbrRestRequest).ScriptBlock.ToString()
            $script:handler.Enqueue(200,'{"data":[{"id":"one"}],"total":2,"next":"c2"}')
            $script:handler.Enqueue(200,'{"data":[{"id":"two"}],"total":2,"next":null}')
            $r = Invoke-VbrRestRequest FutureCursor
            $r.Data.Count | Should -Be 2
            $script:handler.Requests[0] | Should -Be 'GET /api/v1/cursor'
            $script:handler.Requests[1] | Should -Be 'GET /api/v1/cursor?cursor=c2'
            (Get-Command Invoke-VbrRestRequest).ScriptBlock.ToString() | Should -Be $before
        }
    }
}
}
}
