# Version: 0.1.0
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$pester = Get-Module -ListAvailable Pester |
    Where-Object Version -ge ([version]'5.5.0') |
    Sort-Object Version -Descending |
    Select-Object -First 1

if ($null -eq $pester) {
    throw 'Pester 5.5 or later is required. Install-Module Pester -Scope CurrentUser -Force'
}

Import-Module $pester.Path -Force
$configuration = New-PesterConfiguration
$configuration.Run.Path = Join-Path $PSScriptRoot '..\tests'
$configuration.Run.PassThru = $true
$configuration.Output.Verbosity = 'Detailed'
$configuration.TestResult.Enabled = $true
$configuration.TestResult.OutputPath = Join-Path $PSScriptRoot '..\TestResults\Pester.xml'
$configuration.TestResult.OutputFormat = 'NUnitXml'

$result = Invoke-Pester -Configuration $configuration
if ($result.FailedCount -gt 0) {
    throw "$($result.FailedCount) Pester test(s) failed."
}
