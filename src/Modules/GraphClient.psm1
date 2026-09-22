Set-StrictMode -Version Latest

$script:CachedGraphToken = $null
$script:CachedGraphTokenExpiry = [DateTimeOffset]::MinValue

function New-ClassifiedException {
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

function Get-ManagedIdentityGraphToken {
    [CmdletBinding()]
    param()

    if ($script:CachedGraphToken -and $script:CachedGraphTokenExpiry -gt [DateTimeOffset]::UtcNow.AddMinutes(5)) {
        return $script:CachedGraphToken
    }

    if ([string]::IsNullOrWhiteSpace($env:IDENTITY_ENDPOINT) -or [string]::IsNullOrWhiteSpace($env:IDENTITY_HEADER)) {
        throw (New-ClassifiedException -Message 'Managed Identity endpoint variables are unavailable. Run this operation in Azure Functions or mock token acquisition in tests.' -ErrorClass 'Microsoft Graph authentication error')
    }

    $resource = [uri]::EscapeDataString('https://graph.microsoft.com/')
    $uri = "$($env:IDENTITY_ENDPOINT)?api-version=2019-08-01&resource=$resource"

    try {
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers @{
            'X-IDENTITY-HEADER' = $env:IDENTITY_HEADER
            Metadata = 'true'
        } -TimeoutSec 30
    }
    catch {
        throw (New-ClassifiedException -Message "Managed Identity token acquisition failed: $($_.Exception.Message)" -ErrorClass 'Microsoft Graph authentication error' -InnerException $_.Exception)
    }

    if ([string]::IsNullOrWhiteSpace($response.access_token)) {
        throw (New-ClassifiedException -Message 'Managed Identity token response did not contain an access token.' -ErrorClass 'Microsoft Graph authentication error')
    }

    $script:CachedGraphToken = $response.access_token
    $expiry = 0L
    if ([long]::TryParse([string]$response.expires_on, [ref]$expiry)) {
        $script:CachedGraphTokenExpiry = [DateTimeOffset]::FromUnixTimeSeconds($expiry)
    }
    else {
        $script:CachedGraphTokenExpiry = [DateTimeOffset]::UtcNow.AddMinutes(30)
    }

    return $script:CachedGraphToken
}

function Get-HttpStatusCode {
    param([System.Exception]$Exception)

    if ($Exception.Data.Contains('StatusCode')) {
        return [int]$Exception.Data['StatusCode']
    }

    $responseProperty = $Exception.PSObject.Properties['Response']
    if ($null -eq $responseProperty -or $null -eq $responseProperty.Value) {
        return $null
    }

    try {
        return [int]$responseProperty.Value.StatusCode
    }
    catch {
        return $null
    }
}

function Get-RetryAfterSeconds {
    param(
        [System.Exception]$Exception,
        [int]$FallbackSeconds
    )

    if ($Exception.Data.Contains('RetryAfter')) {
        return [math]::Clamp([int]$Exception.Data['RetryAfter'], 1, 300)
    }

    try {
        $values = $Exception.Response.Headers.GetValues('Retry-After')
        $retryAfter = 0
        if ([int]::TryParse([string]($values | Select-Object -First 1), [ref]$retryAfter)) {
            return [math]::Clamp($retryAfter, 1, 300)
        }
    }
    catch {
    }

    return $FallbackSeconds
}

function Invoke-GraphRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('GET', 'POST')]
        [string]$Method,
        [Parameter(Mandatory)]
        [string]$Uri,
        [AllowNull()]
        [object]$Body,
        [Parameter(Mandatory)]
        [pscustomobject]$Configuration
    )

    $retryStartedAt = [DateTimeOffset]::UtcNow
    $retryBudgetSeconds = 240

    for ($attempt = 0; $attempt -le $Configuration.MaxRetryCount; $attempt++) {
        try {
            $token = Get-ManagedIdentityGraphToken
            $parameters = @{
                Method = $Method
                Uri = $Uri
                Headers = @{
                    Authorization = "Bearer $token"
                    Accept = 'application/json'
                }
                TimeoutSec = $Configuration.GraphRequestTimeoutSeconds
            }
            if ($null -ne $Body) {
                $parameters.ContentType = 'application/json'
                $parameters.Body = $Body | ConvertTo-Json -Depth 10 -Compress
            }

            return Invoke-RestMethod @parameters
        }
        catch {
            $statusCode = Get-HttpStatusCode -Exception $_.Exception
            $isLastAttempt = $attempt -ge $Configuration.MaxRetryCount

            if ($statusCode -eq 401) {
                $script:CachedGraphToken = $null
                if (-not $isLastAttempt) {
                    continue
                }
                throw (New-ClassifiedException -Message 'Microsoft Graph returned HTTP 401. Verify Managed Identity token acquisition and tenant context.' -ErrorClass 'Microsoft Graph authentication error' -InnerException $_.Exception)
            }
            if ($statusCode -eq 403) {
                throw (New-ClassifiedException -Message 'Microsoft Graph returned HTTP 403. Verify DeviceManagementServiceConfig.ReadWrite.All is assigned to the Function Managed Identity.' -ErrorClass 'Microsoft Graph authorization error' -InnerException $_.Exception)
            }
            if ($statusCode -eq 404) {
                throw (New-ClassifiedException -Message "Microsoft Graph resource was not found: $Uri" -ErrorClass 'Microsoft Graph permanent error' -InnerException $_.Exception)
            }

            $isThrottled = $statusCode -eq 429
            $isTransient = $null -eq $statusCode -or $statusCode -ge 500
            if (($isThrottled -or $isTransient) -and -not $isLastAttempt) {
                $baseDelay = [math]::Pow(2, $attempt) * $Configuration.RetryBaseDelaySeconds
                $jitter = Get-Random -Minimum 0.0 -Maximum 1.0
                $delay = [int][math]::Ceiling($baseDelay + $jitter)
                if ($isThrottled) {
                    $delay = Get-RetryAfterSeconds -Exception $_.Exception -FallbackSeconds $delay
                }
                $remainingRetryBudget = $retryBudgetSeconds - [int]([DateTimeOffset]::UtcNow - $retryStartedAt).TotalSeconds
                if ($remainingRetryBudget -le 0) {
                    $isLastAttempt = $true
                }
                else {
                    $delay = [math]::Min($delay, $remainingRetryBudget)
                }
            }

            if (($isThrottled -or $isTransient) -and -not $isLastAttempt) {
                Start-Sleep -Seconds $delay
                continue
            }

            if ($isThrottled) {
                throw (New-ClassifiedException -Message 'Microsoft Graph throttling retries were exhausted.' -ErrorClass 'Microsoft Graph throttling error' -InnerException $_.Exception)
            }
            if ($isTransient) {
                throw (New-ClassifiedException -Message 'Microsoft Graph transient retries were exhausted.' -ErrorClass 'Microsoft Graph transient error' -InnerException $_.Exception)
            }

            throw (New-ClassifiedException -Message "Microsoft Graph request failed with HTTP $statusCode." -ErrorClass 'Microsoft Graph permanent error' -InnerException $_.Exception)
        }
    }
}

function Get-AutopilotDevices {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Configuration
    )

    $uri = "https://graph.microsoft.com/$($Configuration.GraphApiVersion)/deviceManagement/windowsAutopilotDeviceIdentities?`$select=id,serialNumber,displayName,groupTag,userPrincipalName,addressableUserName,enrollmentState,managedDeviceId,azureActiveDirectoryDeviceId&`$top=100"
    $devices = [System.Collections.Generic.List[object]]::new()

    while (-not [string]::IsNullOrWhiteSpace($uri)) {
        $response = Invoke-GraphRequest -Method GET -Uri $uri -Configuration $Configuration
        foreach ($device in @($response.value)) {
            $devices.Add($device)
        }
        $nextLink = $response.PSObject.Properties['@odata.nextLink']
        $uri = if ($null -ne $nextLink) { [string]$nextLink.Value } else { $null }
    }

    return @($devices)
}

function Update-AutopilotDeviceProperties {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AutopilotDeviceId,
        [Parameter(Mandatory)]
        [hashtable]$Properties,
        [Parameter(Mandatory)]
        [pscustomobject]$Configuration
    )

    $escapedId = [uri]::EscapeDataString($AutopilotDeviceId)
    $uri = "https://graph.microsoft.com/$($Configuration.GraphApiVersion)/deviceManagement/windowsAutopilotDeviceIdentities/$escapedId/updateDeviceProperties"
    Invoke-GraphRequest -Method POST -Uri $uri -Body $Properties -Configuration $Configuration | Out-Null
}

Export-ModuleMember -Function Get-ManagedIdentityGraphToken, Invoke-GraphRequest, Get-AutopilotDevices, Update-AutopilotDeviceProperties
