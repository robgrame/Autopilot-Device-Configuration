Set-StrictMode -Version Latest

$script:CachedStorageToken = $null
$script:CachedStorageTokenExpiry = [DateTimeOffset]::MinValue

function New-InventoryException {
    param(
        [string]$Message,
        [string]$ErrorClass,
        [System.Exception]$InnerException
    )

    $exception = if ($null -ne $InnerException) {
        [System.InvalidOperationException]::new($Message, $InnerException)
    }
    else {
        [System.InvalidOperationException]::new($Message)
    }
    $exception.Data['ErrorClass'] = $ErrorClass
    return $exception
}

function ConvertFrom-InventoryJson {
    param(
        [Parameter(Mandatory)]
        [string]$Json,
        [Parameter(Mandatory)]
        [string]$Source
    )

    if ([System.Text.Encoding]::UTF8.GetByteCount($Json) -gt 5MB) {
        throw (New-InventoryException -Message "Inventory source '$Source' exceeds the 5 MB MVP limit." -ErrorClass 'inventory validation error')
    }

    try {
        return @(ConvertFrom-Json -InputObject $Json -Depth 20)
    }
    catch {
        throw (New-InventoryException -Message "Inventory source '$Source' is not valid JSON." -ErrorClass 'inventory validation error' -InnerException $_.Exception)
    }
}

function Get-ManagedIdentityStorageToken {
    [CmdletBinding()]
    param()

    if ($script:CachedStorageToken -and $script:CachedStorageTokenExpiry -gt [DateTimeOffset]::UtcNow.AddMinutes(5)) {
        return $script:CachedStorageToken
    }

    if ([string]::IsNullOrWhiteSpace($env:IDENTITY_ENDPOINT) -or [string]::IsNullOrWhiteSpace($env:IDENTITY_HEADER)) {
        throw (New-InventoryException -Message 'Managed Identity endpoint variables are unavailable for Blob inventory access.' -ErrorClass 'configuration error')
    }

    $resource = [uri]::EscapeDataString('https://storage.azure.com/')
    $uri = "$($env:IDENTITY_ENDPOINT)?api-version=2019-08-01&resource=$resource"

    try {
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers @{
            'X-IDENTITY-HEADER' = $env:IDENTITY_HEADER
            Metadata = 'true'
        } -TimeoutSec 30
    }
    catch {
        throw (New-InventoryException -Message "Managed Identity token acquisition for Azure Storage failed: $($_.Exception.Message)" -ErrorClass 'configuration error' -InnerException $_.Exception)
    }

    if ([string]::IsNullOrWhiteSpace($response.access_token)) {
        throw (New-InventoryException -Message 'Managed Identity token response for Azure Storage did not contain an access token.' -ErrorClass 'configuration error')
    }

    $script:CachedStorageToken = $response.access_token
    $expiry = 0L
    if ([long]::TryParse([string]$response.expires_on, [ref]$expiry)) {
        $script:CachedStorageTokenExpiry = [DateTimeOffset]::FromUnixTimeSeconds($expiry)
    }
    else {
        $script:CachedStorageTokenExpiry = [DateTimeOffset]::UtcNow.AddMinutes(30)
    }

    return $script:CachedStorageToken
}

function Get-StorageBlobInventoryContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BlobUrl,
        [Parameter(Mandatory)]
        [pscustomobject]$Configuration
    )

    for ($attempt = 0; $attempt -le $Configuration.MaxRetryCount; $attempt++) {
        try {
            $token = Get-ManagedIdentityStorageToken
            $response = Invoke-WebRequest -Method Get -Uri $BlobUrl -Headers @{
                Authorization = "Bearer $token"
                'x-ms-date' = [DateTime]::UtcNow.ToString('R')
                'x-ms-version' = '2023-11-03'
            } -TimeoutSec $Configuration.GraphRequestTimeoutSeconds
            return [string]$response.Content
        }
        catch {
            $statusCode = if ($_.Exception.Data.Contains('StatusCode')) {
                [int]$_.Exception.Data['StatusCode']
            }
            else {
                try { [int]$_.Exception.Response.StatusCode } catch { $null }
            }
            $isLastAttempt = $attempt -ge $Configuration.MaxRetryCount

            if ($statusCode -eq 401) {
                $script:CachedStorageToken = $null
                if (-not $isLastAttempt) {
                    continue
                }
                throw (New-InventoryException -Message 'Azure Storage returned HTTP 401 while downloading inventory. Verify the Function Managed Identity token context.' -ErrorClass 'inventory authentication error' -InnerException $_.Exception)
            }
            if ($statusCode -eq 403) {
                throw (New-InventoryException -Message 'Azure Storage returned HTTP 403 while downloading inventory. Verify Blob data access for the Function Managed Identity.' -ErrorClass 'inventory authorization error' -InnerException $_.Exception)
            }
            if ($statusCode -eq 404) {
                throw (New-InventoryException -Message 'The configured inventory Blob was not found (HTTP 404). Publish inventory before running the Function.' -ErrorClass 'configuration error' -InnerException $_.Exception)
            }

            $isTransient = $null -eq $statusCode -or $statusCode -eq 408 -or $statusCode -eq 429 -or $statusCode -ge 500
            if ($isTransient -and -not $isLastAttempt) {
                $delay = [int][math]::Ceiling(([math]::Pow(2, $attempt) * $Configuration.RetryBaseDelaySeconds) + (Get-Random -Minimum 0.0 -Maximum 1.0))
                Start-Sleep -Seconds $delay
                continue
            }
            if ($isTransient) {
                throw (New-InventoryException -Message "Azure Storage transient retries were exhausted while downloading inventory (HTTP $statusCode)." -ErrorClass 'inventory transient error' -InnerException $_.Exception)
            }

            throw (New-InventoryException -Message "Azure Storage inventory request failed with HTTP $statusCode." -ErrorClass 'inventory permanent error' -InnerException $_.Exception)
        }
    }
}

function Get-DeviceInventoryRecords {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Configuration,
        [scriptblock]$GetBlobContentOperation = {
            param($BlobUrl, $ProviderConfiguration)
            Get-StorageBlobInventoryContent -BlobUrl $BlobUrl -Configuration $ProviderConfiguration
        }
    )

    switch ($Configuration.InventoryProvider) {
        'package-json' {
            if (-not (Test-Path -LiteralPath $Configuration.InventoryPath -PathType Leaf)) {
                $exception = [System.IO.FileNotFoundException]::new("Inventory file '$($Configuration.InventoryPath)' was not found.")
                $exception.Data['ErrorClass'] = 'configuration error'
                throw $exception
            }
            $records = ConvertFrom-InventoryJson `
                -Json (Get-Content -LiteralPath $Configuration.InventoryPath -Raw -Encoding UTF8) `
                -Source $Configuration.InventoryPath
        }
        'storage-blob' {
            $blobContent = & $GetBlobContentOperation $Configuration.InventoryStorageBlobUrl $Configuration
            $records = ConvertFrom-InventoryJson -Json ([string]$blobContent) -Source $Configuration.InventoryStorageBlobUrl
        }
        default {
            $exception = [System.NotSupportedException]::new("Inventory provider '$($Configuration.InventoryProvider)' is not supported.")
            $exception.Data['ErrorClass'] = 'configuration error'
            throw $exception
        }
    }

    if (@($records).Count -eq 0) {
        Write-Output -NoEnumerate @()
        return
    }

    return $records
}

Export-ModuleMember -Function Get-ManagedIdentityStorageToken, Get-StorageBlobInventoryContent, Get-DeviceInventoryRecords
