$script:ModuleRoot = Join-Path $PSScriptRoot '..\src\Modules'
Import-Module (Join-Path $script:ModuleRoot 'GraphClient.psm1') -Force

BeforeAll {
    $moduleRoot = Join-Path $PSScriptRoot '..\src\Modules'
    Import-Module (Join-Path $moduleRoot 'Configuration.psm1') -Force
    Import-Module (Join-Path $moduleRoot 'InventoryProvider.psm1') -Force
    Import-Module (Join-Path $moduleRoot 'Validation.psm1') -Force
    Import-Module (Join-Path $moduleRoot 'Eligibility.psm1') -Force
    Import-Module (Join-Path $moduleRoot 'Logging.psm1') -Force
    Import-Module (Join-Path $moduleRoot 'Processor.psm1') -Force

    function New-TestConfiguration {
        param(
            [bool]$DryRun = $true,
            [string[]]$PilotSerialNumbers = @()
        )

        [pscustomobject]@{
            DryRun = $DryRun
            InventoryProvider = 'package-json'
            InventoryPath = ''
            DeviceNameValidationPattern = '^[A-Za-z][A-Za-z0-9-]{0,14}$'
            GroupTagValidationPattern = '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'
            PilotSerialNumbers = @($PilotSerialNumbers)
            AllowedProvisioningMethods = @('Autopilot', 'CloudNative')
            AllowedLifecycleStates = @('Approved', 'Pilot', 'Ready')
            AllowedJoinTypes = @('MicrosoftEntraJoined', 'Pending')
            GraphApiVersion = 'v1.0'
            MaxRetryCount = 2
            RetryBaseDelaySeconds = 1
            GraphRequestTimeoutSeconds = 30
            LogLevel = 'Information'
        }
    }

    function New-InventoryRecord {
        param(
            [string]$SerialNumber = 'SERIAL001',
            [AllowNull()][string]$DeviceName = 'IT-LT-00123',
            [AllowNull()][string]$GroupTag = 'NATIVE-IT-LAPTOP',
            [bool]$EligibleForAutomation = $true,
            [AllowNull()][string]$ProvisioningMethod = 'Autopilot',
            [AllowNull()][string]$LifecycleState = 'Pilot',
            [AllowNull()][string]$JoinType = 'MicrosoftEntraJoined',
            [bool]$Legacy = $false,
            [bool]$Excluded = $false,
            [bool]$ConflictingProvisioningInfo = $false
        )

        [pscustomobject]@{
            SerialNumber = $SerialNumber
            DeviceName = $DeviceName
            GroupTag = $GroupTag
            EligibleForAutomation = $EligibleForAutomation
            ProvisioningMethod = $ProvisioningMethod
            LifecycleState = $LifecycleState
            JoinType = $JoinType
            Legacy = $Legacy
            Excluded = $Excluded
            ConflictingProvisioningInfo = $ConflictingProvisioningInfo
        }
    }

    function New-AutopilotDevice {
        param(
            [string]$Id = 'device-1',
            [string]$SerialNumber = 'SERIAL001',
            [string]$DisplayName = 'OLD-NAME',
            [string]$GroupTag = 'OLD-TAG'
        )

        [pscustomobject]@{
            id = $Id
            serialNumber = $SerialNumber
            displayName = $DisplayName
            groupTag = $GroupTag
            userPrincipalName = 'pilot.user@example.invalid'
            addressableUserName = 'Pilot User'
            enrollmentState = 'enrolled'
            managedDeviceId = 'managed-1'
            azureActiveDirectoryDeviceId = 'entra-1'
        }
    }

    function Invoke-TestProcessing {
        param(
            [object[]]$Inventory,
            [object[]]$Devices,
            [bool]$DryRun = $true,
            [scriptblock]$UpdateOperation = { param($Id, $Properties, $Config) },
            [string[]]$PilotSerialNumbers = @()
        )

        Invoke-AutopilotProcessing `
            -Configuration (New-TestConfiguration -DryRun $DryRun -PilotSerialNumbers $PilotSerialNumbers) `
            -InventoryRecords $Inventory `
            -CorrelationId ([guid]::NewGuid().ToString()) `
            -GetAutopilotDevicesOperation { param($Config) $Devices }.GetNewClosure() `
            -UpdateAutopilotDeviceOperation $UpdateOperation
    }
}

Describe 'Serial correlation and validation' {
    It 'matches an exact serial number' {
        $result = Invoke-TestProcessing -Inventory @(New-InventoryRecord) -Devices @(New-AutopilotDevice)
        $result.UniqueMatches | Should -Be 1
        $result.ProposedUpdates | Should -Be 1
    }

    It 'matches serial numbers case-insensitively' {
        $result = Invoke-TestProcessing -Inventory @(New-InventoryRecord -SerialNumber 'serial001') -Devices @(New-AutopilotDevice -SerialNumber 'SERIAL001')
        $result.UniqueMatches | Should -Be 1
    }

    It 'matches serial numbers after trimming whitespace' {
        $result = Invoke-TestProcessing -Inventory @(New-InventoryRecord -SerialNumber '  SERIAL001  ') -Devices @(New-AutopilotDevice)
        $result.UniqueMatches | Should -Be 1
    }

    It 'reports an inventory device that is absent from Autopilot' {
        $result = Invoke-TestProcessing -Inventory @(New-InventoryRecord) -Devices @()
        $result.UnmatchedInventoryRecords | Should -Be 1
    }

    It 'reports an Autopilot device that is absent from inventory' {
        $result = Invoke-TestProcessing -Inventory @(New-InventoryRecord) -Devices @(New-AutopilotDevice -SerialNumber 'OTHER001')
        $result.UnmatchedAutopilotDevices | Should -Be 1
    }

    It 'rejects duplicate inventory serial numbers' {
        $inventory = @(
            New-InventoryRecord -DeviceName 'IT-LT-00123'
            New-InventoryRecord -SerialNumber ' serial001 ' -DeviceName 'IT-LT-00124'
        )
        $result = Invoke-TestProcessing -Inventory $inventory -Devices @(New-AutopilotDevice)
        $result.InvalidInventoryRecords | Should -Be 2
        $result.UniqueMatches | Should -Be 0
    }

    It 'rejects duplicate Autopilot serial-number matches' {
        $devices = @(
            New-AutopilotDevice -Id 'device-1'
            New-AutopilotDevice -Id 'device-2' -SerialNumber 'serial001'
        )
        $result = Invoke-TestProcessing -Inventory @(New-InventoryRecord) -Devices $devices
        $result.UniqueMatches | Should -Be 0
        $result.SkippedDevices | Should -Be 1
    }

    It 'rejects a missing Device Name' {
        $result = Invoke-TestProcessing -Inventory @(New-InventoryRecord -DeviceName $null) -Devices @(New-AutopilotDevice)
        $result.InvalidInventoryRecords | Should -Be 1
    }

    It 'rejects an invalid Device Name' {
        $result = Invoke-TestProcessing -Inventory @(New-InventoryRecord -DeviceName 'INVALID DEVICE NAME') -Devices @(New-AutopilotDevice)
        $result.InvalidInventoryRecords | Should -Be 1
    }

    It 'rejects a missing Group Tag' {
        $result = Invoke-TestProcessing -Inventory @(New-InventoryRecord -GroupTag $null) -Devices @(New-AutopilotDevice)
        $result.InvalidInventoryRecords | Should -Be 1
    }

    It 'rejects an invalid Group Tag' {
        $result = Invoke-TestProcessing -Inventory @(New-InventoryRecord -GroupTag 'INVALID TAG!') -Devices @(New-AutopilotDevice)
        $result.InvalidInventoryRecords | Should -Be 1
    }

    It 'rejects duplicate desired Device Names' {
        $inventory = @(
            New-InventoryRecord -SerialNumber 'SERIAL001' -DeviceName 'IT-LT-00123'
            New-InventoryRecord -SerialNumber 'SERIAL002' -DeviceName 'it-lt-00123'
        )
        $result = Invoke-TestProcessing -Inventory $inventory -Devices @()
        $result.InvalidInventoryRecords | Should -Be 2
    }
}

Describe 'Eligibility protection' {
    It 'skips EligibleForAutomation false' {
        $result = Invoke-TestProcessing -Inventory @(New-InventoryRecord -EligibleForAutomation $false) -Devices @(New-AutopilotDevice)
        $result.SkippedDevices | Should -Be 1
        $result.ProposedUpdates | Should -Be 0
    }

    It 'fails closed when eligibility metadata is ambiguous' {
        $result = Invoke-TestProcessing -Inventory @(New-InventoryRecord -JoinType $null) -Devices @(New-AutopilotDevice)
        $result.SkippedDevices | Should -Be 1
        $result.ProposedUpdates | Should -Be 0
    }

    It 'excludes an existing Hybrid or legacy device' {
        $result = Invoke-TestProcessing -Inventory @(New-InventoryRecord -JoinType 'HybridMicrosoftEntraJoined' -Legacy $true) -Devices @(New-AutopilotDevice)
        $result.SkippedDevices | Should -Be 1
        $result.ProposedUpdates | Should -Be 0
    }

    It 'limits processing to the pilot allow-list' {
        $result = Invoke-TestProcessing -Inventory @(New-InventoryRecord) -Devices @(New-AutopilotDevice) -PilotSerialNumbers @('SERIAL999')
        $result.SkippedDevices | Should -Be 1
        $result.ProposedUpdates | Should -Be 0
    }
}

Describe 'Idempotent update decisions' {
    It 'returns an auditable summary for an empty inventory' {
        $result = Invoke-TestProcessing -Inventory @() -Devices @(New-AutopilotDevice)
        $result.InventoryRecordsLoaded | Should -Be 0
        $result.UnmatchedAutopilotDevices | Should -Be 1
        $result.FailedUpdates | Should -Be 0
    }

    It 'marks an already compliant device as compliant' {
        $device = New-AutopilotDevice -DisplayName 'IT-LT-00123' -GroupTag 'NATIVE-IT-LAPTOP'
        $result = Invoke-TestProcessing -Inventory @(New-InventoryRecord) -Devices @($device)
        $result.CompliantDevices | Should -Be 1
        $result.ProposedUpdates | Should -Be 0
    }

    It 'updates only Device Name when Group Tag is compliant' {
        $script:UpdateCalls = @()
        $update = {
            param($Id, $Properties, $Config)
            $script:UpdateCalls += ,$Properties
        }
        $device = New-AutopilotDevice -DisplayName 'OLD-NAME' -GroupTag 'NATIVE-IT-LAPTOP'
        $result = Invoke-TestProcessing -Inventory @(New-InventoryRecord) -Devices @($device) -DryRun $false -UpdateOperation $update
        $result.SuccessfulUpdates | Should -Be 1
        $script:UpdateCalls[0].displayName | Should -Be 'IT-LT-00123'
        $script:UpdateCalls[0].groupTag | Should -Be 'NATIVE-IT-LAPTOP'
    }

    It 'updates only Group Tag when Device Name is compliant' {
        $script:UpdateCalls = @()
        $update = {
            param($Id, $Properties, $Config)
            $script:UpdateCalls += ,$Properties
        }
        $device = New-AutopilotDevice -DisplayName 'IT-LT-00123' -GroupTag 'OLD-TAG'
        $result = Invoke-TestProcessing -Inventory @(New-InventoryRecord) -Devices @($device) -DryRun $false -UpdateOperation $update
        $result.SuccessfulUpdates | Should -Be 1
        $script:UpdateCalls[0].displayName | Should -Be 'IT-LT-00123'
        $script:UpdateCalls[0].groupTag | Should -Be 'NATIVE-IT-LAPTOP'
    }

    It 'updates both properties when both differ' {
        $script:UpdateCalls = @()
        $update = {
            param($Id, $Properties, $Config)
            $script:UpdateCalls += ,$Properties
        }
        $result = Invoke-TestProcessing -Inventory @(New-InventoryRecord) -Devices @(New-AutopilotDevice) -DryRun $false -UpdateOperation $update
        $result.SuccessfulUpdates | Should -Be 1
        $script:UpdateCalls[0].displayName | Should -Be 'IT-LT-00123'
        $script:UpdateCalls[0].groupTag | Should -Be 'NATIVE-IT-LAPTOP'
        $script:UpdateCalls[0].userPrincipalName | Should -Be 'pilot.user@example.invalid'
    }

    It 'omits empty user-assignment fields from the update body' {
        $script:UpdateCalls = @()
        $update = {
            param($Id, $Properties, $Config)
            $script:UpdateCalls += ,$Properties
        }
        $device = New-AutopilotDevice
        $device.userPrincipalName = ''
        $device.addressableUserName = ''

        $result = Invoke-TestProcessing -Inventory @(New-InventoryRecord) -Devices @($device) -DryRun $false -UpdateOperation $update
        $result.SuccessfulUpdates | Should -Be 1
        $script:UpdateCalls[0].ContainsKey('userPrincipalName') | Should -BeFalse
        $script:UpdateCalls[0].ContainsKey('addressableUserName') | Should -BeFalse
    }

    It 'prevents Microsoft Graph updates in dry-run mode' {
        $script:UpdateCount = 0
        $update = { param($Id, $Properties, $Config) $script:UpdateCount++ }
        $result = Invoke-TestProcessing -Inventory @(New-InventoryRecord) -Devices @(New-AutopilotDevice) -UpdateOperation $update
        $result.ProposedUpdates | Should -Be 1
        $script:UpdateCount | Should -Be 0
    }

    It 'continues after one device update fails' {
        $inventory = @(
            New-InventoryRecord -SerialNumber 'SERIAL001' -DeviceName 'IT-LT-00123'
            New-InventoryRecord -SerialNumber 'SERIAL002' -DeviceName 'IT-LT-00124'
        )
        $devices = @(
            New-AutopilotDevice -Id 'device-1' -SerialNumber 'SERIAL001'
            New-AutopilotDevice -Id 'device-2' -SerialNumber 'SERIAL002'
        )
        $script:UpdateAttempt = 0
        $update = {
            param($Id, $Properties, $Config)
            $script:UpdateAttempt++
            if ($script:UpdateAttempt -eq 1) {
                throw 'Simulated device failure'
            }
        }
        $result = Invoke-TestProcessing -Inventory $inventory -Devices $devices -DryRun $false -UpdateOperation $update
        $result.FailedUpdates | Should -Be 1
        $result.SuccessfulUpdates | Should -Be 1
    }

    It 'is idempotent after an update is applied' {
        $device = New-AutopilotDevice
        $counter = [pscustomobject]@{ Value = 0 }
        $update = {
            param($Id, $Properties, $Config)
            $counter.Value++
            if ($Properties.ContainsKey('displayName')) { $device.displayName = $Properties.displayName }
            if ($Properties.ContainsKey('groupTag')) { $device.groupTag = $Properties.groupTag }
        }.GetNewClosure()

        $first = Invoke-TestProcessing -Inventory @(New-InventoryRecord) -Devices @($device) -DryRun $false -UpdateOperation $update
        $second = Invoke-TestProcessing -Inventory @(New-InventoryRecord) -Devices @($device) -DryRun $false -UpdateOperation $update

        $first.SuccessfulUpdates | Should -Be 1
        $second.CompliantDevices | Should -Be 1
        $counter.Value | Should -Be 1
    }
}

Describe 'Microsoft Graph retry handling' {
    InModuleScope GraphClient {
        BeforeEach {
            $configuration = [pscustomobject]@{
                MaxRetryCount = 2
                RetryBaseDelaySeconds = 1
                GraphRequestTimeoutSeconds = 30
            }
            Mock Get-ManagedIdentityGraphToken { 'token' }
            Mock Start-Sleep {}
        }

        It 'retries HTTP 429 throttling and honors bounded retry behavior' {
            $script:RequestCount = 0
            Mock Invoke-RestMethod {
                $script:RequestCount++
                if ($script:RequestCount -lt 3) {
                    $exception = [System.Exception]::new('throttled')
                    $exception.Data['StatusCode'] = 429
                    $exception.Data['RetryAfter'] = 1
                    throw $exception
                }
                [pscustomobject]@{ value = @() }
            }

            Invoke-GraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/test' -Configuration $configuration | Out-Null
            Should -Invoke Invoke-RestMethod -Times 3 -Exactly
            Should -Invoke Start-Sleep -Times 2 -Exactly
        }

        It 'sends the managed-identity token as a Bearer authorization header' {
            $script:CapturedHeaders = $null
            Mock Invoke-RestMethod {
                param($Method, $Uri, $Headers, $TimeoutSec)
                $script:CapturedHeaders = $Headers
                [pscustomobject]@{ value = @() }
            }

            Invoke-GraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/test' -Configuration $configuration | Out-Null
            $script:CapturedHeaders.Authorization | Should -Be 'Bearer token'
        }

        It 'retries a transient HTTP 5xx failure' {
            $script:RequestCount = 0
            Mock Invoke-RestMethod {
                $script:RequestCount++
                if ($script:RequestCount -eq 1) {
                    $exception = [System.Exception]::new('temporary')
                    $exception.Data['StatusCode'] = 503
                    throw $exception
                }
                [pscustomobject]@{ value = @() }
            }

            Invoke-GraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/test' -Configuration $configuration | Out-Null
            Should -Invoke Invoke-RestMethod -Times 2 -Exactly
        }

        It 'retries a network exception without an HTTP response' {
            $script:RequestCount = 0
            Mock Invoke-RestMethod {
                $script:RequestCount++
                if ($script:RequestCount -lt 3) {
                    throw [System.Net.Http.HttpRequestException]::new('network unavailable')
                }
                [pscustomobject]@{ value = @() }
            }

            Invoke-GraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/test' -Configuration $configuration | Out-Null
            Should -Invoke Invoke-RestMethod -Times 3 -Exactly
            Should -Invoke Start-Sleep -Times 2 -Exactly
        }

        It 'does not retry a permanent HTTP 4xx failure' {
            Mock Invoke-RestMethod {
                $exception = [System.Exception]::new('bad request')
                $exception.Data['StatusCode'] = 400
                throw $exception
            }

            { Invoke-GraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/test' -Configuration $configuration } |
                Should -Throw '*HTTP 400*'
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly
            Should -Invoke Start-Sleep -Times 0 -Exactly
        }

        It 'follows every Microsoft Graph pagination link' {
            $config = [pscustomobject]@{ GraphApiVersion = 'v1.0' }
            Mock Invoke-GraphRequest {
                param($Method, $Uri, $Configuration)
                if ($Uri -eq 'https://graph.microsoft.com/next-page') {
                    return [pscustomobject]@{
                        value = @([pscustomobject]@{ id = 'two'; serialNumber = 'SERIAL002' })
                    }
                }
                return [pscustomobject]@{
                    value = @([pscustomobject]@{ id = 'one'; serialNumber = 'SERIAL001' })
                    '@odata.nextLink' = 'https://graph.microsoft.com/next-page'
                }
            }

            $devices = @(Get-AutopilotDevices -Configuration $config)
            $devices.Count | Should -Be 2
            Should -Invoke Invoke-GraphRequest -Times 2 -Exactly
        }
    }
}

Describe 'Configuration and inventory safety' {
    It 'blocks write mode when the pilot allow-list is empty' {
        $previousDryRun = $env:DRY_RUN
        $previousPilot = $env:PILOT_SERIAL_NUMBERS
        try {
            $env:DRY_RUN = 'false'
            $env:PILOT_SERIAL_NUMBERS = ''
            { Get-AutopilotConfiguration -FunctionRoot $TestDrive } | Should -Throw '*PILOT_SERIAL_NUMBERS*'
        }
        finally {
            $env:DRY_RUN = $previousDryRun
            $env:PILOT_SERIAL_NUMBERS = $previousPilot
        }
    }

    It 'loads inventory records through the package-json provider' {
        $path = Join-Path $TestDrive 'inventory.json'
        @(
            [pscustomobject]@{
                SerialNumber = 'SERIAL001'
                DeviceName = 'IT-LT-00123'
                GroupTag = 'NATIVE-IT-LAPTOP'
                EligibleForAutomation = $true
            }
        ) | ConvertTo-Json | Set-Content -LiteralPath $path -Encoding UTF8

        $configuration = [pscustomobject]@{
            InventoryProvider = 'package-json'
            InventoryPath = $path
        }
        $records = @(Get-DeviceInventoryRecords -Configuration $configuration)
        $records.Count | Should -Be 1
        $records[0].SerialNumber | Should -Be 'SERIAL001'
    }
}
