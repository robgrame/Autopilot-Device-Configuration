Set-StrictMode -Version Latest

function Normalize-SerialNumber {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$SerialNumber
    )

    $original = if ($null -eq $SerialNumber) { '' } else { [string]$SerialNumber }
    $normalized = $original.Trim().ToUpperInvariant()
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        $exception = [System.ArgumentException]::new('Serial number is empty after trimming.')
        $exception.Data['ErrorClass'] = 'inventory validation error'
        throw $exception
    }

    [pscustomobject]@{
        Original = $original
        Normalized = $normalized
    }
}

function Test-DeviceName {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$DeviceName,
        [Parameter(Mandatory)]
        [string]$Pattern
    )

    $value = if ($null -eq $DeviceName) { '' } else { ([string]$DeviceName).Trim() }
    $reasons = [System.Collections.Generic.List[string]]::new()

    if ([string]::IsNullOrWhiteSpace($value)) {
        $reasons.Add('Device Name is required.')
    }
    else {
        if ($value.Length -gt 15) {
            $reasons.Add('Device Name exceeds the Windows Autopilot limit of 15 characters.')
        }
        if ($value -notmatch '^[A-Za-z0-9-]+$') {
            $reasons.Add('Device Name contains unsupported characters.')
        }
        if ($value -match '^\d+$') {
            $reasons.Add('Device Name cannot contain only numbers.')
        }
        try {
            if ($value -notmatch $Pattern) {
                $reasons.Add('Device Name does not match the configured organizational naming pattern.')
            }
        }
        catch {
            $exception = [System.ArgumentException]::new('DEVICE_NAME_VALIDATION_PATTERN is not a valid regular expression.', $_.Exception)
            $exception.Data['ErrorClass'] = 'configuration error'
            throw $exception
        }
    }

    [pscustomobject]@{
        IsValid = $reasons.Count -eq 0
        Value = $value
        Reasons = @($reasons)
    }
}

function Test-GroupTag {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$GroupTag,
        [Parameter(Mandatory)]
        [string]$Pattern
    )

    $value = if ($null -eq $GroupTag) { '' } else { ([string]$GroupTag).Trim() }
    $reasons = [System.Collections.Generic.List[string]]::new()

    if ([string]::IsNullOrWhiteSpace($value)) {
        $reasons.Add('Group Tag is required.')
    }
    else {
        if ($value.Length -gt 64) {
            $reasons.Add('Group Tag exceeds the documented 64-character limit.')
        }
        try {
            if ($value -notmatch $Pattern) {
                $reasons.Add('Group Tag does not match the configured naming pattern or allow-list.')
            }
        }
        catch {
            $exception = [System.ArgumentException]::new('GROUP_TAG_VALIDATION_PATTERN is not a valid regular expression.', $_.Exception)
            $exception.Data['ErrorClass'] = 'configuration error'
            throw $exception
        }
    }

    [pscustomobject]@{
        IsValid = $reasons.Count -eq 0
        Value = $value
        Reasons = @($reasons)
    }
}

Export-ModuleMember -Function Normalize-SerialNumber, Test-DeviceName, Test-GroupTag
