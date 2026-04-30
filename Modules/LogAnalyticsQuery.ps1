# Equivalent of services/logAnalyticsQuery.ts
# Returns an array of [pscustomobject] AppAccessSummary records.

$script:SignInTables = @(
    @{ TableName = 'SigninLogs';                      AccessType = 'Interactive'      },
    @{ TableName = 'AADNonInteractiveUserSignInLogs'; AccessType = 'NonInteractive'   },
    @{ TableName = 'AADServicePrincipalSignInLogs';   AccessType = 'ServicePrincipal' },
    @{ TableName = 'AADManagedIdentitySignInLogs';    AccessType = 'ManagedIdentity'  }
)

function Build-KqlQuery {
    param(
        [Parameter(Mandatory)] [string] $TableName,
        [Parameter(Mandatory)] [string] $StartDate,
        [Parameter(Mandatory)] [string] $EndDate
    )
    return @"
$TableName
| where CreatedDateTime >= datetime($StartDate) and CreatedDateTime < datetime($EndDate)
| summarize
    TotalSignIns = count(),
    SuccessCount = countif(ResultType == "0"),
    FailureCount = countif(ResultType != "0")
by AppDisplayName, AppId
"@
}

function Get-LogAnalyticsAccessToken {
    # Tries managed identity first (in Azure), falls back to current Az context (local dev).
    if ($env:IDENTITY_ENDPOINT -and $env:IDENTITY_HEADER) {
        $uri = "$($env:IDENTITY_ENDPOINT)?resource=https://api.loganalytics.io&api-version=2019-08-01"
        $headers = @{ 'X-IDENTITY-HEADER' = $env:IDENTITY_HEADER }
        $resp = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers
        return $resp.access_token
    }

    $token = Get-AzAccessToken -ResourceUrl 'https://api.loganalytics.io'
    return $token.Token
}

function Get-SignInSummaries {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]   $WorkspaceId,
        [Parameter(Mandatory)] [DateTime] $TargetDate
    )

    $startDateObj = $TargetDate.ToUniversalTime().Date
    $endDateObj   = $startDateObj.AddDays(1)
    $startDate    = $startDateObj.ToString("yyyy-MM-ddTHH:mm:ssZ")
    $endDate      = $endDateObj.ToString("yyyy-MM-ddTHH:mm:ssZ")
    $summaryDate  = $startDateObj.ToString('yyyy-MM-dd')

    $token = Get-LogAnalyticsAccessToken
    $headers = @{
        Authorization                = "Bearer $token"
        'Content-Type'               = 'application/json'
        'Prefer'                     = 'wait=300'
    }
    $uri = "https://api.loganalytics.io/v1/workspaces/$WorkspaceId/query"

    $allResults = New-Object System.Collections.Generic.List[object]
    $errors     = New-Object System.Collections.Generic.List[string]

    foreach ($config in $script:SignInTables) {
        $kql = Build-KqlQuery -TableName $config.TableName -StartDate $startDate -EndDate $endDate
        Write-Host "Querying $($config.TableName)..."

        $body = @{
            query     = $kql
            timespan  = "$startDate/$endDate"
        } | ConvertTo-Json -Depth 5

        try {
            $resp = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $body -ErrorAction Stop

            if (-not $resp.tables -or $resp.tables.Count -eq 0) {
                Write-Host "  $($config.TableName): no data"
                continue
            }

            $table = $resp.tables[0]
            $colNames = @($table.columns | ForEach-Object { $_.name })
            $appDisplayNameIdx = $colNames.IndexOf('AppDisplayName')
            $appIdIdx          = $colNames.IndexOf('AppId')
            $totalIdx          = $colNames.IndexOf('TotalSignIns')
            $successIdx        = $colNames.IndexOf('SuccessCount')
            $failureIdx        = $colNames.IndexOf('FailureCount')

            $count = 0
            foreach ($row in $table.rows) {
                $allResults.Add([pscustomobject]@{
                    SummaryDate    = $summaryDate
                    AppDisplayName = [string]($row[$appDisplayNameIdx])
                    AppId          = [string]($row[$appIdIdx])
                    AccessType     = $config.AccessType
                    TotalSignIns   = [int]($row[$totalIdx])
                    SuccessCount   = [int]($row[$successIdx])
                    FailureCount   = [int]($row[$failureIdx])
                })
                $count++
            }
            Write-Host "  $($config.TableName): $count apps found"
        }
        catch {
            $msg = "$($config.TableName) failed: $($_.Exception.Message)"
            Write-Warning $msg
            $errors.Add($msg)
        }
    }

    if ($errors.Count -gt 0) {
        Write-Warning "Completed with $($errors.Count) error(s): $([string]::Join(' | ', $errors))"
    }

    return ,$allResults.ToArray()
}
