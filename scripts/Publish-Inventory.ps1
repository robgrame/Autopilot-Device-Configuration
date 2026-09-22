# Version: 0.2.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SubscriptionId,
    [Parameter(Mandatory)]
    [string]$ResourceGroupName,
    [Parameter(Mandatory)]
    [string]$FunctionAppName,
    [Parameter(Mandatory)]
    [string]$StorageAccountName,
    [Parameter(Mandatory)]
    [string]$InventoryPath,
    [string]$ContainerName = 'inventory',
    [string]$BlobName = 'inventory.json'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $InventoryPath -PathType Leaf)) {
    throw "Inventory file '$InventoryPath' was not found."
}
if ((Get-Item -LiteralPath $InventoryPath).Length -gt 5MB) {
    throw 'Inventory file exceeds the 5 MB MVP limit.'
}

try {
    $records = @(Get-Content -LiteralPath $InventoryPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 20)
}
catch {
    throw "Inventory file is not valid JSON: $($_.Exception.Message)"
}

if ($records.Count -eq 0) {
    Write-Warning 'The inventory is empty. The Function will perform no inventory-driven updates.'
}

foreach ($record in $records) {
    foreach ($requiredProperty in @('SerialNumber', 'DeviceName', 'GroupTag', 'EligibleForAutomation')) {
        if ($null -eq $record.PSObject.Properties[$requiredProperty]) {
            throw "An inventory record is missing required property '$requiredProperty'."
        }
    }
}

az account set --subscription $SubscriptionId
if ($LASTEXITCODE -ne 0) {
    throw "Unable to select Azure subscription '$SubscriptionId'."
}

az storage container create `
    --account-name $StorageAccountName `
    --name $ContainerName `
    --auth-mode login `
    --output none
if ($LASTEXITCODE -ne 0) {
    throw "Unable to create or access Blob container '$ContainerName'. Verify Storage Blob Data Contributor access."
}

az storage blob upload `
    --account-name $StorageAccountName `
    --container-name $ContainerName `
    --name $BlobName `
    --file $InventoryPath `
    --auth-mode login `
    --overwrite true `
    --content-type 'application/json' `
    --output none
if ($LASTEXITCODE -ne 0) {
    throw 'Inventory Blob upload failed.'
}

$blobUrl = "https://$StorageAccountName.blob.core.windows.net/$ContainerName/$BlobName"
az functionapp config appsettings set `
    --subscription $SubscriptionId `
    --resource-group $ResourceGroupName `
    --name $FunctionAppName `
    --settings 'INVENTORY_PROVIDER=storage-blob' "INVENTORY_STORAGE_BLOB_URL=$blobUrl" `
    --output none
if ($LASTEXITCODE -ne 0) {
    throw 'Inventory provider configuration failed after Blob upload. Verify Contributor access to the Function App; the uploaded Blob is unchanged.'
}

try {
    azd env set INVENTORY_PROVIDER storage-blob
    if ($LASTEXITCODE -ne 0) {
        throw 'azd env set failed.'
    }
}
catch {
    Write-Warning 'The Function App now uses Blob inventory, but the provider could not be persisted in the local AZD environment. Run "azd env set INVENTORY_PROVIDER storage-blob" before the next provision operation.'
}

Write-Host "Inventory published to '$blobUrl'."
Write-Host "Function App '$FunctionAppName' now uses the storage-blob inventory provider."
