# Version: 0.1.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$EnvironmentName,
    [Parameter(Mandatory)]
    [string]$SubscriptionId,
    [string]$Location = 'westeurope'
)

$ErrorActionPreference = 'Stop'

azd auth login --check-status
if ($LASTEXITCODE -ne 0) {
    azd auth login
    if ($LASTEXITCODE -ne 0) { throw 'azd authentication failed.' }
}

az account show --output none
if ($LASTEXITCODE -ne 0) {
    throw 'Azure CLI is not authenticated. Run az login in the intended customer tenant.'
}

az account set --subscription $SubscriptionId
if ($LASTEXITCODE -ne 0) {
    throw "Azure CLI cannot select subscription '$SubscriptionId'."
}

$selectedSubscriptionId = az account show --query id --output tsv
if ($LASTEXITCODE -ne 0 -or $selectedSubscriptionId -ne $SubscriptionId) {
    throw "Azure CLI subscription verification failed. Expected '$SubscriptionId', received '$selectedSubscriptionId'."
}

azd env select $EnvironmentName 2>$null
if ($LASTEXITCODE -ne 0) {
    azd env new $EnvironmentName --no-prompt
    if ($LASTEXITCODE -ne 0) { throw "Unable to create AZD environment '$EnvironmentName'." }
}

azd env set AZURE_SUBSCRIPTION_ID $SubscriptionId
azd env set AZURE_LOCATION $Location

azd provision --no-prompt
if ($LASTEXITCODE -ne 0) { throw 'Azure infrastructure provisioning failed.' }

Write-Host 'Waiting 60 seconds for Azure RBAC propagation before code deployment.'
Start-Sleep -Seconds 60

azd deploy --no-prompt
if ($LASTEXITCODE -ne 0) { throw 'Azure Function deployment failed.' }

$functionName = azd env get-value AZURE_FUNCTION_NAME
$resourceGroup = azd env get-value AZURE_RESOURCE_GROUP

$settings = az functionapp config appsettings list `
    --subscription $SubscriptionId `
    --resource-group $resourceGroup `
    --name $functionName `
    --query "[?name=='DRY_RUN'].value | [0]" `
    --output tsv
if ($LASTEXITCODE -ne 0 -or $settings -ne 'true') {
    throw 'Deployment safety check failed: DRY_RUN is not true.'
}

Write-Host "Deployment completed with DRY_RUN=true. Function App: $functionName"
Write-Host "Next: run scripts\Grant-GraphPermission.ps1 as Privileged Role Administrator."
