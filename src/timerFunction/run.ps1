param($myTimer)

$ErrorActionPreference = 'Stop'

$correlationId = [guid]::NewGuid().ToString()
$startedAt = [DateTimeOffset]::UtcNow

try {
    $configuration = Get-AutopilotConfiguration -FunctionRoot (Split-Path $PSScriptRoot -Parent)
    Write-StructuredLog -Level Information -EventName 'ExecutionStarted' -CorrelationId $correlationId -Data @{
        StartedAt = $startedAt
        DryRun = $configuration.DryRun
        IsPastDue = [bool]$myTimer.IsPastDue
        InventoryProvider = $configuration.InventoryProvider
        GraphApiVersion = $configuration.GraphApiVersion
    }

    $inventoryRecords = Get-DeviceInventoryRecords -Configuration $configuration
    $summary = Invoke-AutopilotProcessing `
        -Configuration $configuration `
        -InventoryRecords $inventoryRecords `
        -CorrelationId $correlationId

    $summary
}
catch {
    Write-StructuredLog -Level Error -EventName 'ExecutionFailed' -CorrelationId $correlationId -Data @{
        ErrorClass = if ($_.Exception.Data['ErrorClass']) { $_.Exception.Data['ErrorClass'] } else { 'unexpected processing error' }
        Message = $_.Exception.Message
        DryRun = if ($null -ne $configuration) { $configuration.DryRun } else { $null }
    }
    throw
}
