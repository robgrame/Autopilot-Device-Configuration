# Version: 0.1.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ResourceGroupName,
    [Parameter(Mandatory)]
    [string]$FunctionAppName,
    [Parameter(Mandatory)]
    [bool]$Enabled
)

$ErrorActionPreference = 'Stop'
$disabled = (-not $Enabled).ToString().ToLowerInvariant()

az functionapp config appsettings set `
    --resource-group $ResourceGroupName `
    --name $FunctionAppName `
    --settings "AzureWebJobs.timerFunction.Disabled=$disabled" `
    --output none
if ($LASTEXITCODE -ne 0) {
    throw 'Failed to update timer trigger state.'
}

Write-Host "Timer trigger enabled state is now '$Enabled' for '$FunctionAppName'."
