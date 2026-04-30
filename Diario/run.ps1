param($Timer)

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/../Modules/LogAnalyticsQuery.ps1"
. "$PSScriptRoot/../Modules/LogAnalyticsIngest.ps1"

$sourceWorkspaceId = $env:SOURCE_WORKSPACE_ID
$endpoint          = $env:DATA_COLLECTION_ENDPOINT
$ruleId            = $env:DATA_COLLECTION_RULE_ID
$streamName        = if ([string]::IsNullOrWhiteSpace($env:CUSTOM_TABLE_STREAM_NAME)) { 'Custom-AppAccessSummary_CL' } else { $env:CUSTOM_TABLE_STREAM_NAME }

if (-not $sourceWorkspaceId -or -not $endpoint -or -not $ruleId) {
    throw "Missing required environment variables: SOURCE_WORKSPACE_ID, DATA_COLLECTION_ENDPOINT, DATA_COLLECTION_RULE_ID"
}

# D-1 em UTC, normalizado para 00:00:00
$yesterday = [DateTime]::UtcNow.Date.AddDays(-1)
$summaryDate = $yesterday.ToString('yyyy-MM-dd')

Write-Host "Querying sign-in summaries for $summaryDate..."

$summaries = Get-SignInSummaries -WorkspaceId $sourceWorkspaceId -TargetDate $yesterday

$byType = @{}
foreach ($s in $summaries) {
    if (-not $byType.ContainsKey($s.AccessType)) { $byType[$s.AccessType] = 0 }
    $byType[$s.AccessType] += 1
}
$breakdown = ($byType.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', '
Write-Host "Results for ${summaryDate}: $breakdown, Total=$($summaries.Count) records"

Send-AppAccessSummaries -Endpoint $endpoint -RuleId $ruleId -StreamName $streamName -Summaries $summaries

Write-Host "Successfully uploaded $($summaries.Count) summary records."
