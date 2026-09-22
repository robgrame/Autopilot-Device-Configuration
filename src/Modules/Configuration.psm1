Set-StrictMode -Version Latest

function ConvertTo-StrictBoolean {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value,
        [bool]$Default = $false,
        [string]$SettingName = 'value'
    )

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return $Default
    }

    if ($Value -is [bool]) {
        return $Value
    }

    switch (([string]$Value).Trim().ToLowerInvariant()) {
        'true' { return $true }
        'false' { return $false }
        default {
            $exception = [System.ArgumentException]::new("$SettingName must be 'true' or 'false'.")
            $exception.Data['ErrorClass'] = 'configuration error'
            throw $exception
        }
    }
}

function Get-IntegerSetting {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Value,
        [int]$Default,
        [int]$Minimum,
        [int]$Maximum,
        [string]$SettingName
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Default
    }

    $parsed = 0
    if (-not [int]::TryParse($Value, [ref]$parsed) -or $parsed -lt $Minimum -or $parsed -gt $Maximum) {
        $exception = [System.ArgumentException]::new("$SettingName must be an integer from $Minimum to $Maximum.")
        $exception.Data['ErrorClass'] = 'configuration error'
        throw $exception
    }

    return $parsed
}

function Get-AutopilotConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FunctionRoot
    )

    $dryRun = ConvertTo-StrictBoolean -Value $env:DRY_RUN -Default $true -SettingName 'DRY_RUN'
    $provider = if ([string]::IsNullOrWhiteSpace($env:INVENTORY_PROVIDER)) { 'package-json' } else { $env:INVENTORY_PROVIDER.Trim().ToLowerInvariant() }
    if ($provider -notin @('package-json', 'storage-blob')) {
        $exception = [System.ArgumentException]::new("Unsupported INVENTORY_PROVIDER '$provider'.")
        $exception.Data['ErrorClass'] = 'configuration error'
        throw $exception
    }

    $inventoryRelativePath = if ([string]::IsNullOrWhiteSpace($env:INVENTORY_PATH)) { 'inventory/sample-inventory.json' } else { $env:INVENTORY_PATH.Trim() }
    $inventoryPath = if ([System.IO.Path]::IsPathRooted($inventoryRelativePath)) {
        $inventoryRelativePath
    }
    else {
        Join-Path $FunctionRoot $inventoryRelativePath
    }

    $inventoryStorageBlobUrl = if ([string]::IsNullOrWhiteSpace($env:INVENTORY_STORAGE_BLOB_URL)) { '' } else { $env:INVENTORY_STORAGE_BLOB_URL.Trim() }
    if ($provider -eq 'storage-blob') {
        $parsedBlobUri = $null
        $isValidBlobUri = [uri]::TryCreate($inventoryStorageBlobUrl, [System.UriKind]::Absolute, [ref]$parsedBlobUri)
        $pathSegments = if ($isValidBlobUri) { @($parsedBlobUri.AbsolutePath.Trim('/') -split '/') } else { @() }
        $hasInvalidPath = @($pathSegments).Count -lt 2 -or @($pathSegments | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0
        if (-not $isValidBlobUri -or
            $parsedBlobUri.Scheme -ne 'https' -or
            $parsedBlobUri.Host -notmatch '^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]\.blob\.core\.windows\.net$' -or
            $hasInvalidPath -or
            -not [string]::IsNullOrWhiteSpace($parsedBlobUri.Query)) {
            $exception = [System.ArgumentException]::new('INVENTORY_STORAGE_BLOB_URL must identify a Blob in public Azure over HTTPS and must not contain a query string or SAS token.')
            $exception.Data['ErrorClass'] = 'configuration error'
            throw $exception
        }
    }

    $graphApiVersion = if ([string]::IsNullOrWhiteSpace($env:GRAPH_API_VERSION)) { 'v1.0' } else { $env:GRAPH_API_VERSION.Trim() }
    if ($graphApiVersion -notin @('v1.0', 'beta')) {
        $exception = [System.ArgumentException]::new('GRAPH_API_VERSION must be v1.0 or beta.')
        $exception.Data['ErrorClass'] = 'configuration error'
        throw $exception
    }

    $pilotSerialNumbers = @(
        if (-not [string]::IsNullOrWhiteSpace($env:PILOT_SERIAL_NUMBERS)) {
            $env:PILOT_SERIAL_NUMBERS.Split(',', [System.StringSplitOptions]::RemoveEmptyEntries) |
                ForEach-Object { $_.Trim().ToUpperInvariant() } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                Select-Object -Unique
        }
    )

    if (-not $dryRun -and $pilotSerialNumbers.Count -eq 0) {
        $exception = [System.ArgumentException]::new('PILOT_SERIAL_NUMBERS must contain at least one serial number before DRY_RUN can be disabled.')
        $exception.Data['ErrorClass'] = 'configuration error'
        throw $exception
    }

    [pscustomobject]@{
        DryRun = $dryRun
        InventoryProvider = $provider
        InventoryPath = $inventoryPath
        InventoryStorageBlobUrl = $inventoryStorageBlobUrl
        DeviceNameValidationPattern = if ([string]::IsNullOrWhiteSpace($env:DEVICE_NAME_VALIDATION_PATTERN)) { '^[A-Za-z][A-Za-z0-9-]{0,14}$' } else { $env:DEVICE_NAME_VALIDATION_PATTERN }
        GroupTagValidationPattern = if ([string]::IsNullOrWhiteSpace($env:GROUP_TAG_VALIDATION_PATTERN)) { '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$' } else { $env:GROUP_TAG_VALIDATION_PATTERN }
        PilotSerialNumbers = $pilotSerialNumbers
        AllowedProvisioningMethods = @('Autopilot', 'CloudNative')
        AllowedLifecycleStates = @('Approved', 'Pilot', 'Ready')
        AllowedJoinTypes = @('MicrosoftEntraJoined', 'Pending')
        GraphApiVersion = $graphApiVersion
        MaxRetryCount = Get-IntegerSetting -Value $env:MAX_RETRY_COUNT -Default 4 -Minimum 0 -Maximum 10 -SettingName 'MAX_RETRY_COUNT'
        RetryBaseDelaySeconds = Get-IntegerSetting -Value $env:RETRY_BASE_DELAY_SECONDS -Default 2 -Minimum 1 -Maximum 60 -SettingName 'RETRY_BASE_DELAY_SECONDS'
        GraphRequestTimeoutSeconds = Get-IntegerSetting -Value $env:GRAPH_REQUEST_TIMEOUT_SECONDS -Default 100 -Minimum 10 -Maximum 300 -SettingName 'GRAPH_REQUEST_TIMEOUT_SECONDS'
        LogLevel = if ([string]::IsNullOrWhiteSpace($env:LOG_LEVEL)) { 'Information' } else { $env:LOG_LEVEL.Trim() }
    }
}

Export-ModuleMember -Function ConvertTo-StrictBoolean, Get-AutopilotConfiguration
