# Version: 0.1.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ResourceGroupName,
    [Parameter(Mandatory)]
    [string]$FunctionAppName,
    [string]$PermissionValue = 'DeviceManagementServiceConfig.ReadWrite.All'
)

$ErrorActionPreference = 'Stop'

function Invoke-AzCliJson {
    param([Parameter(Mandatory)][string[]]$Arguments)

    $output = & az @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI failed: $($output -join [Environment]::NewLine)"
    }
    return ($output -join [Environment]::NewLine) | ConvertFrom-Json
}

$functionIdentity = Invoke-AzCliJson -Arguments @(
    'functionapp', 'identity', 'show',
    '--resource-group', $ResourceGroupName,
    '--name', $FunctionAppName,
    '--output', 'json'
)

if ([string]::IsNullOrWhiteSpace($functionIdentity.principalId)) {
    throw "Function App '$FunctionAppName' does not have a system-assigned Managed Identity."
}

$graphQuery = [uri]::EscapeDataString("appId eq '00000003-0000-0000-c000-000000000000'")
$graphServicePrincipals = Invoke-AzCliJson -Arguments @(
    'rest', '--method', 'GET',
    '--url', "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=$graphQuery&`$select=id,appId,displayName,appRoles",
    '--output', 'json'
)

$graphServicePrincipal = @($graphServicePrincipals.value) | Where-Object appId -eq '00000003-0000-0000-c000-000000000000'
if ($graphServicePrincipal.Count -ne 1) {
    throw "Expected one Microsoft Graph service principal but found $($graphServicePrincipal.Count)."
}

$appRole = @($graphServicePrincipal.appRoles) | Where-Object {
    $_.value -eq $PermissionValue -and
    $_.isEnabled -eq $true -and
    'Application' -in $_.allowedMemberTypes
}
if ($appRole.Count -ne 1) {
    throw "Microsoft Graph application role '$PermissionValue' was not found uniquely."
}

$assignments = Invoke-AzCliJson -Arguments @(
    'rest', '--method', 'GET',
    '--url', "https://graph.microsoft.com/v1.0/servicePrincipals/$($functionIdentity.principalId)/appRoleAssignments",
    '--output', 'json'
)

$existing = @($assignments.value) | Where-Object {
    $_.resourceId -eq $graphServicePrincipal.id -and $_.appRoleId -eq $appRole.id
}

if ($existing.Count -eq 0) {
    $body = @{
        principalId = $functionIdentity.principalId
        resourceId = $graphServicePrincipal.id
        appRoleId = $appRole.id
    } | ConvertTo-Json -Compress

    Invoke-AzCliJson -Arguments @(
        'rest', '--method', 'POST',
        '--url', "https://graph.microsoft.com/v1.0/servicePrincipals/$($functionIdentity.principalId)/appRoleAssignments",
        '--headers', 'Content-Type=application/json',
        '--body', $body,
        '--output', 'json'
    ) | Out-Null
    Write-Host "Assigned '$PermissionValue' to Managed Identity $($functionIdentity.principalId)."
}
else {
    Write-Host "Permission '$PermissionValue' is already assigned to Managed Identity $($functionIdentity.principalId)."
}

$verifiedAssignments = Invoke-AzCliJson -Arguments @(
    'rest', '--method', 'GET',
    '--url', "https://graph.microsoft.com/v1.0/servicePrincipals/$($functionIdentity.principalId)/appRoleAssignments",
    '--output', 'json'
)

$verified = @($verifiedAssignments.value) | Where-Object {
    $_.resourceId -eq $graphServicePrincipal.id -and $_.appRoleId -eq $appRole.id
}
if ($verified.Count -ne 1) {
    throw "Permission assignment verification failed for '$PermissionValue'."
}

Write-Host "Verified '$PermissionValue' for Function App '$FunctionAppName'."
