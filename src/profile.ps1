$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$moduleRoot = Join-Path $PSScriptRoot 'Modules'
Import-Module (Join-Path $moduleRoot 'Configuration.psm1')
Import-Module (Join-Path $moduleRoot 'InventoryProvider.psm1')
Import-Module (Join-Path $moduleRoot 'Validation.psm1')
Import-Module (Join-Path $moduleRoot 'Eligibility.psm1')
Import-Module (Join-Path $moduleRoot 'Logging.psm1')
Import-Module (Join-Path $moduleRoot 'GraphClient.psm1')
Import-Module (Join-Path $moduleRoot 'Processor.psm1')
