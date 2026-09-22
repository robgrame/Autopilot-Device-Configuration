Set-StrictMode -Version Latest

function Write-StructuredLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Debug', 'Information', 'Warning', 'Error')]
        [string]$Level,
        [Parameter(Mandatory)]
        [string]$EventName,
        [Parameter(Mandatory)]
        [string]$CorrelationId,
        [hashtable]$Data = @{}
    )

    $payload = [ordered]@{
        Timestamp = [DateTimeOffset]::UtcNow.ToString('O')
        Level = $Level
        EventName = $EventName
        CorrelationId = $CorrelationId
    }

    foreach ($key in $Data.Keys) {
        if ($key -match '(?i)token|authorization|credential|secret|password') {
            continue
        }
        $payload[$key] = $Data[$key]
    }

    $json = $payload | ConvertTo-Json -Depth 10 -Compress
    switch ($Level) {
        'Warning' { Write-Warning $json }
        'Error' { Write-Error $json -ErrorAction Continue }
        default { Write-Information $json -InformationAction Continue }
    }
}

Export-ModuleMember -Function Write-StructuredLog
