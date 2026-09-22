Set-StrictMode -Version Latest

function Get-ObjectPropertyValue {
    param(
        [Parameter(Mandatory)]
        [object]$InputObject,
        [Parameter(Mandatory)]
        [string]$Name,
        [AllowNull()]
        [object]$Default = $null
    )

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $Default
    }
    return $property.Value
}

function New-ExecutionSummary {
    param(
        [string]$CorrelationId,
        [bool]$DryRun,
        [DateTimeOffset]$StartedAt
    )

    [ordered]@{
        CorrelationId = $CorrelationId
        StartedAt = $StartedAt.ToString('O')
        EndedAt = $null
        DurationMilliseconds = 0
        DryRun = $DryRun
        InventoryRecordsLoaded = 0
        ValidInventoryRecords = 0
        InvalidInventoryRecords = 0
        AutopilotDevicesEvaluated = 0
        UniqueMatches = 0
        UnmatchedInventoryRecords = 0
        UnmatchedAutopilotDevices = 0
        CompliantDevices = 0
        ProposedUpdates = 0
        SuccessfulUpdates = 0
        SkippedDevices = 0
        FailedUpdates = 0
    }
}

function Complete-ExecutionSummary {
    param(
        [hashtable]$Summary,
        [DateTimeOffset]$StartedAt,
        [string]$CorrelationId
    )

    $endedAt = [DateTimeOffset]::UtcNow
    $Summary.EndedAt = $endedAt.ToString('O')
    $Summary.DurationMilliseconds = [math]::Round(($endedAt - $StartedAt).TotalMilliseconds)
    Write-StructuredLog -Level Information -EventName 'ExecutionSummary' -CorrelationId $CorrelationId -Data $Summary
    return [pscustomobject]$Summary
}

function Invoke-AutopilotProcessing {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Configuration,
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$InventoryRecords,
        [Parameter(Mandatory)]
        [string]$CorrelationId,
        [scriptblock]$GetAutopilotDevicesOperation = {
            param($Config)
            Get-AutopilotDevices -Configuration $Config
        },
        [scriptblock]$UpdateAutopilotDeviceOperation = {
            param($DeviceId, $Properties, $Config)
            Update-AutopilotDeviceProperties -AutopilotDeviceId $DeviceId -Properties $Properties -Configuration $Config
        }
    )

    $startedAt = [DateTimeOffset]::UtcNow
    $summary = New-ExecutionSummary -CorrelationId $CorrelationId -DryRun $Configuration.DryRun -StartedAt $startedAt
    $summary.InventoryRecordsLoaded = $InventoryRecords.Count

    $preparedInventory = [System.Collections.Generic.List[object]]::new()
    foreach ($record in $InventoryRecords) {
        $validationReasons = [System.Collections.Generic.List[string]]::new()
        $normalization = $null
        try {
            $normalization = Normalize-SerialNumber -SerialNumber (Get-ObjectPropertyValue -InputObject $record -Name 'SerialNumber')
        }
        catch {
            $validationReasons.Add($_.Exception.Message)
        }

        $preparedInventory.Add([pscustomobject]@{
            Record = $record
            OriginalSerial = if ($null -ne $normalization) { $normalization.Original } else { [string](Get-ObjectPropertyValue -InputObject $record -Name 'SerialNumber' -Default '') }
            NormalizedSerial = if ($null -ne $normalization) { $normalization.Normalized } else { $null }
            ValidationReasons = $validationReasons
        })
    }

    $serialCounts = @{}
    foreach ($item in $preparedInventory | Where-Object { -not [string]::IsNullOrWhiteSpace($_.NormalizedSerial) }) {
        $serialCounts[$item.NormalizedSerial] = 1 + [int]($serialCounts[$item.NormalizedSerial])
    }

    $deviceNameCounts = @{}
    foreach ($item in $preparedInventory) {
        $deviceName = [string](Get-ObjectPropertyValue -InputObject $item.Record -Name 'DeviceName' -Default '')
        if (-not [string]::IsNullOrWhiteSpace($deviceName)) {
            $key = $deviceName.Trim().ToUpperInvariant()
            $deviceNameCounts[$key] = 1 + [int]($deviceNameCounts[$key])
        }
    }

    foreach ($item in $preparedInventory) {
        if ($item.NormalizedSerial -and $serialCounts[$item.NormalizedSerial] -gt 1) {
            $item.ValidationReasons.Add('Duplicate or conflicting inventory serial number.')
        }

        $deviceName = [string](Get-ObjectPropertyValue -InputObject $item.Record -Name 'DeviceName' -Default '')
        if (-not [string]::IsNullOrWhiteSpace($deviceName) -and $deviceNameCounts[$deviceName.Trim().ToUpperInvariant()] -gt 1) {
            $item.ValidationReasons.Add('Duplicate desired Device Name in the inventory batch.')
        }
    }

    try {
        $autopilotDevices = @(& $GetAutopilotDevicesOperation $Configuration)
    }
    catch {
        Complete-ExecutionSummary -Summary $summary -StartedAt $startedAt -CorrelationId $CorrelationId | Out-Null
        throw
    }

    $summary.AutopilotDevicesEvaluated = $autopilotDevices.Count
    $autopilotBySerial = @{}
    foreach ($device in $autopilotDevices) {
        try {
            $normalized = (Normalize-SerialNumber -SerialNumber (Get-ObjectPropertyValue -InputObject $device -Name 'serialNumber')).Normalized
            if (-not $autopilotBySerial.ContainsKey($normalized)) {
                $autopilotBySerial[$normalized] = [System.Collections.Generic.List[object]]::new()
            }
            $autopilotBySerial[$normalized].Add($device)
        }
        catch {
            Write-StructuredLog -Level Warning -EventName 'AutopilotRecordSkipped' -CorrelationId $CorrelationId -Data @{
                RequestedAction = 'SKIP'
                Result = 'SKIPPED'
                Reason = $_.Exception.Message
            }
        }
    }

    $inventorySerials = @($preparedInventory | Where-Object NormalizedSerial | ForEach-Object NormalizedSerial | Select-Object -Unique)
    $summary.UnmatchedAutopilotDevices = @(
        foreach ($key in $autopilotBySerial.Keys) {
            if ($key -notin $inventorySerials) {
                $autopilotBySerial[$key]
            }
        }
    ).Count

    foreach ($item in $preparedInventory) {
        $record = $item.Record
        $serialForLog = if ($item.OriginalSerial) { $item.OriginalSerial } else { '<empty>' }

        if ($item.ValidationReasons.Count -gt 0) {
            $summary.InvalidInventoryRecords++
            $summary.SkippedDevices++
            Write-StructuredLog -Level Warning -EventName 'DeviceValidationFailed' -CorrelationId $CorrelationId -Data @{
                SerialNumber = $serialForLog
                RequestedAction = 'SKIP'
                Result = 'SKIPPED'
                Reason = ($item.ValidationReasons -join ' ')
            }
            continue
        }

        $deviceNameValidation = Test-DeviceName `
            -DeviceName (Get-ObjectPropertyValue -InputObject $record -Name 'DeviceName') `
            -Pattern $Configuration.DeviceNameValidationPattern
        $groupTagValidation = Test-GroupTag `
            -GroupTag (Get-ObjectPropertyValue -InputObject $record -Name 'GroupTag') `
            -Pattern $Configuration.GroupTagValidationPattern

        if (-not $deviceNameValidation.IsValid -or -not $groupTagValidation.IsValid) {
            $summary.InvalidInventoryRecords++
            $summary.SkippedDevices++
            $reasons = @($deviceNameValidation.Reasons) + @($groupTagValidation.Reasons)
            Write-StructuredLog -Level Warning -EventName 'DeviceValidationFailed' -CorrelationId $CorrelationId -Data @{
                SerialNumber = $serialForLog
                RequestedAction = 'SKIP'
                Result = 'SKIPPED'
                Reason = ($reasons -join ' ')
                ValidationResult = 'Invalid'
            }
            continue
        }

        $summary.ValidInventoryRecords++
        $eligibility = Test-DeviceEligibility -Record $record -NormalizedSerialNumber $item.NormalizedSerial -Configuration $Configuration
        if (-not $eligibility.IsEligible) {
            $summary.SkippedDevices++
            Write-StructuredLog -Level Warning -EventName 'DeviceEligibilityFailed' -CorrelationId $CorrelationId -Data @{
                SerialNumber = $serialForLog
                RequestedAction = 'SKIP'
                Result = 'SKIPPED'
                Reason = ($eligibility.Reasons -join ' ')
                EligibilityResult = 'Ineligible'
            }
            continue
        }

        $autopilotMatches = @(
            if ($autopilotBySerial.ContainsKey($item.NormalizedSerial)) {
                $autopilotBySerial[$item.NormalizedSerial]
            }
        )
        if ($autopilotMatches.Count -eq 0) {
            $summary.UnmatchedInventoryRecords++
            $summary.SkippedDevices++
            Write-StructuredLog -Level Warning -EventName 'DeviceCorrelationFailed' -CorrelationId $CorrelationId -Data @{
                SerialNumber = $serialForLog
                RequestedAction = 'SKIP'
                Result = 'UNMATCHED'
                Reason = 'No exact normalized serial-number match was found in Windows Autopilot.'
            }
            continue
        }
        if ($autopilotMatches.Count -gt 1) {
            $summary.SkippedDevices++
            Write-StructuredLog -Level Warning -EventName 'DeviceCorrelationFailed' -CorrelationId $CorrelationId -Data @{
                SerialNumber = $serialForLog
                RequestedAction = 'SKIP'
                Result = 'AMBIGUOUS'
                Reason = 'Multiple Windows Autopilot identities have the same normalized serial number.'
            }
            continue
        }

        $summary.UniqueMatches++
        $autopilotDevice = $autopilotMatches[0]
        $currentDeviceName = [string](Get-ObjectPropertyValue -InputObject $autopilotDevice -Name 'displayName' -Default '')
        $currentGroupTag = [string](Get-ObjectPropertyValue -InputObject $autopilotDevice -Name 'groupTag' -Default '')
        $deviceNameRequiresUpdate = -not [string]::Equals($currentDeviceName, $deviceNameValidation.Value, [System.StringComparison]::OrdinalIgnoreCase)
        $groupTagRequiresUpdate = -not [string]::Equals($currentGroupTag, $groupTagValidation.Value, [System.StringComparison]::Ordinal)

        if (-not $deviceNameRequiresUpdate -and -not $groupTagRequiresUpdate) {
            $summary.CompliantDevices++
            Write-StructuredLog -Level Information -EventName 'DeviceCompliant' -CorrelationId $CorrelationId -Data @{
                SerialNumber = $serialForLog
                RequestedAction = 'NONE'
                Result = 'COMPLIANT'
                DeviceNameRequiresUpdate = $false
                GroupTagRequiresUpdate = $false
            }
            continue
        }

        $properties = @{
            displayName = if ($deviceNameRequiresUpdate) { $deviceNameValidation.Value } else { $currentDeviceName }
            groupTag = if ($groupTagRequiresUpdate) { $groupTagValidation.Value } else { $currentGroupTag }
        }
        $currentUserPrincipalName = [string](Get-ObjectPropertyValue -InputObject $autopilotDevice -Name 'userPrincipalName' -Default '')
        $currentAddressableUserName = [string](Get-ObjectPropertyValue -InputObject $autopilotDevice -Name 'addressableUserName' -Default '')
        if (-not [string]::IsNullOrWhiteSpace($currentUserPrincipalName)) {
            $properties.userPrincipalName = $currentUserPrincipalName
        }
        if (-not [string]::IsNullOrWhiteSpace($currentAddressableUserName)) {
            $properties.addressableUserName = $currentAddressableUserName
        }

        if ($Configuration.DryRun) {
            $summary.ProposedUpdates++
            Write-StructuredLog -Level Information -EventName 'DeviceWouldUpdate' -CorrelationId $CorrelationId -Data @{
                SerialNumber = $serialForLog
                RequestedAction = 'UPDATE'
                Result = 'WOULD_UPDATE'
                CurrentDeviceName = $currentDeviceName
                DesiredDeviceName = $deviceNameValidation.Value
                CurrentGroupTag = $currentGroupTag
                DesiredGroupTag = $groupTagValidation.Value
                DeviceNameRequiresUpdate = $deviceNameRequiresUpdate
                GroupTagRequiresUpdate = $groupTagRequiresUpdate
                ValidationResult = 'Valid'
                EligibilityResult = 'Eligible'
            }
            continue
        }

        try {
            & $UpdateAutopilotDeviceOperation `
                ([string](Get-ObjectPropertyValue -InputObject $autopilotDevice -Name 'id')) `
                $properties `
                $Configuration
            $summary.SuccessfulUpdates++
            Write-StructuredLog -Level Information -EventName 'DeviceUpdated' -CorrelationId $CorrelationId -Data @{
                SerialNumber = $serialForLog
                RequestedAction = 'UPDATE'
                Result = 'UPDATED'
                PreviousDeviceName = $currentDeviceName
                DesiredDeviceName = $deviceNameValidation.Value
                PreviousGroupTag = $currentGroupTag
                DesiredGroupTag = $groupTagValidation.Value
                DeviceNameRequiresUpdate = $deviceNameRequiresUpdate
                GroupTagRequiresUpdate = $groupTagRequiresUpdate
            }
        }
        catch {
            $summary.FailedUpdates++
            Write-StructuredLog -Level Error -EventName 'DeviceUpdateFailed' -CorrelationId $CorrelationId -Data @{
                SerialNumber = $serialForLog
                RequestedAction = 'UPDATE'
                Result = 'FAILED'
                Reason = $_.Exception.Message
                ErrorClass = if ($_.Exception.Data['ErrorClass']) { $_.Exception.Data['ErrorClass'] } else { 'unexpected processing error' }
            }
        }
    }

    return Complete-ExecutionSummary -Summary $summary -StartedAt $startedAt -CorrelationId $CorrelationId
}

Export-ModuleMember -Function Invoke-AutopilotProcessing
