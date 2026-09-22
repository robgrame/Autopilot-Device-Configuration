Set-StrictMode -Version Latest

function Get-DeviceInventoryRecords {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Configuration
    )

    if ($Configuration.InventoryProvider -ne 'package-json') {
        $exception = [System.NotSupportedException]::new("Inventory provider '$($Configuration.InventoryProvider)' is not supported.")
        $exception.Data['ErrorClass'] = 'configuration error'
        throw $exception
    }

    if (-not (Test-Path -LiteralPath $Configuration.InventoryPath -PathType Leaf)) {
        $exception = [System.IO.FileNotFoundException]::new("Inventory file '$($Configuration.InventoryPath)' was not found.")
        $exception.Data['ErrorClass'] = 'configuration error'
        throw $exception
    }

    try {
        $records = @(Get-Content -LiteralPath $Configuration.InventoryPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 20)
    }
    catch {
        $exception = [System.InvalidDataException]::new("Inventory file '$($Configuration.InventoryPath)' is not valid JSON.", $_.Exception)
        $exception.Data['ErrorClass'] = 'inventory validation error'
        throw $exception
    }

    return ,$records
}

Export-ModuleMember -Function Get-DeviceInventoryRecords
