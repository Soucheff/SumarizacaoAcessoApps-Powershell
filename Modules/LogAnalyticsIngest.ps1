# Equivalent of services/logAnalyticsIngest.ts
# Uploads AppAccessSummary records to a Data Collection Rule via the Logs Ingestion API.

function Get-MonitorIngestionAccessToken {
    if ($env:IDENTITY_ENDPOINT -and $env:IDENTITY_HEADER) {
        $uri = "$($env:IDENTITY_ENDPOINT)?resource=https://monitor.azure.com&api-version=2019-08-01"
        $headers = @{ 'X-IDENTITY-HEADER' = $env:IDENTITY_HEADER }
        $resp = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers
        return $resp.access_token
    }

    $token = Get-AzAccessToken -ResourceUrl 'https://monitor.azure.com'
    return $token.Token
}

function Send-AppAccessSummaries {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Endpoint,
        [Parameter(Mandatory)] [string] $RuleId,
        [Parameter(Mandatory)] [string] $StreamName,
        [Parameter()]          [object[]] $Summaries
    )

    if (-not $Summaries -or $Summaries.Count -eq 0) {
        return
    }

    $now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    $records = foreach ($s in $Summaries) {
        [pscustomobject]@{
            TimeGenerated  = $now
            SummaryDate    = $s.SummaryDate
            AppDisplayName = $s.AppDisplayName
            AppId          = $s.AppId
            AccessType     = $s.AccessType
            TotalSignIns   = $s.TotalSignIns
            SuccessCount   = $s.SuccessCount
            FailureCount   = $s.FailureCount
        }
    }

    $token = Get-MonitorIngestionAccessToken
    $headers = @{
        Authorization  = "Bearer $token"
        'Content-Type' = 'application/json'
    }

    $cleanEndpoint = $Endpoint.TrimEnd('/')
    $uri = "$cleanEndpoint/dataCollectionRules/$RuleId/streams/$StreamName" + "?api-version=2023-01-01"

    # Logs Ingestion API limit is 1 MB per request; chunk to be safe.
    $batchSize = 500
    $total = $records.Count
    for ($i = 0; $i -lt $total; $i += $batchSize) {
        $end = [Math]::Min($i + $batchSize - 1, $total - 1)
        $batch = $records[$i..$end]
        $body = ConvertTo-Json -InputObject @($batch) -Depth 10 -Compress

        try {
            Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $body -ErrorAction Stop | Out-Null
        }
        catch {
            $detail = $_.ErrorDetails.Message
            if (-not $detail) { $detail = $_.Exception.Message }
            Write-Error "Upload error: $detail"
            throw
        }
    }
}
