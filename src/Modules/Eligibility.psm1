Set-StrictMode -Version Latest

function Get-InventoryProperty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Record,
        [Parameter(Mandatory)]
        [string]$Name,
        [AllowNull()]
        [object]$Default = $null
    )

    $property = $Record.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $Default
    }
    return $property.Value
}

function Test-DeviceEligibility {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Record,
        [Parameter(Mandatory)]
        [string]$NormalizedSerialNumber,
        [Parameter(Mandatory)]
        [pscustomobject]$Configuration
    )

    $reasons = [System.Collections.Generic.List[string]]::new()

    if ((Get-InventoryProperty -Record $Record -Name 'EligibleForAutomation' -Default $false) -ne $true) {
        $reasons.Add('EligibleForAutomation is not explicitly true.')
    }
    if ((Get-InventoryProperty -Record $Record -Name 'Legacy' -Default $false) -eq $true) {
        $reasons.Add('Device is explicitly classified as legacy.')
    }
    if ((Get-InventoryProperty -Record $Record -Name 'Excluded' -Default $false) -eq $true) {
        $reasons.Add('Device is explicitly excluded.')
    }
    if ((Get-InventoryProperty -Record $Record -Name 'ConflictingProvisioningInfo' -Default $false) -eq $true) {
        $reasons.Add('Conflicting provisioning information is present.')
    }

    $provisioningMethod = [string](Get-InventoryProperty -Record $Record -Name 'ProvisioningMethod' -Default '')
    if ([string]::IsNullOrWhiteSpace($provisioningMethod)) {
        $reasons.Add('ProvisioningMethod is required for conservative eligibility validation.')
    }
    elseif ($provisioningMethod -notin $Configuration.AllowedProvisioningMethods) {
        $reasons.Add("ProvisioningMethod '$provisioningMethod' is not approved.")
    }

    $lifecycleState = [string](Get-InventoryProperty -Record $Record -Name 'LifecycleState' -Default '')
    if ([string]::IsNullOrWhiteSpace($lifecycleState)) {
        $reasons.Add('LifecycleState is required for conservative eligibility validation.')
    }
    elseif ($lifecycleState -notin $Configuration.AllowedLifecycleStates) {
        $reasons.Add("LifecycleState '$lifecycleState' is not approved.")
    }

    $joinType = [string](Get-InventoryProperty -Record $Record -Name 'JoinType' -Default '')
    if ([string]::IsNullOrWhiteSpace($joinType)) {
        $reasons.Add('JoinType is required because the Autopilot identity alone cannot prove that a device is safe to retag.')
    }
    elseif ($joinType -notin $Configuration.AllowedJoinTypes) {
        $reasons.Add("JoinType '$joinType' is not approved; Hybrid or legacy devices are excluded.")
    }

    if ($Configuration.PilotSerialNumbers.Count -gt 0 -and $NormalizedSerialNumber -notin $Configuration.PilotSerialNumbers) {
        $reasons.Add('Serial number is outside the configured pilot allow-list.')
    }

    [pscustomobject]@{
        IsEligible = $reasons.Count -eq 0
        Reasons = @($reasons)
    }
}

Export-ModuleMember -Function Test-DeviceEligibility
