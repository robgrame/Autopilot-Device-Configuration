# Version: 0.1.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ResourceGroupName,
    [Parameter(Mandatory)]
    [string]$FunctionAppName,
    [Parameter(Mandatory)]
    [bool]$DryRun,
    [string[]]$PilotSerialNumbers = @()
)

$ErrorActionPreference = 'Stop'

if (-not $DryRun -and $PilotSerialNumbers.Count -eq 0) {
    throw 'At least one pilot serial number is required before write mode can be enabled.'
}

$settings = @("DRY_RUN=$($DryRun.ToString().ToLowerInvariant())")
if ($PSBoundParameters.ContainsKey('PilotSerialNumbers')) {
    $pilotValue = ($PilotSerialNumbers | ForEach-Object { $_.Trim() } | Where-Object { $_ }) -join ','
    $settings += "PILOT_SERIAL_NUMBERS=$pilotValue"
}

az functionapp config appsettings set `
    --resource-group $ResourceGroupName `
    --name $FunctionAppName `
    --settings $settings `
    --output none
if ($LASTEXITCODE -ne 0) {
    throw 'Failed to update Function App safety settings.'
}

Write-Host "Updated DRY_RUN=$($DryRun.ToString().ToLowerInvariant()) for '$FunctionAppName'."
