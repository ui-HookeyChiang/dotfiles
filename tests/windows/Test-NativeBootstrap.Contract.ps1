$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($PSVersionTable.PSEdition -ne 'Core' -or $PSVersionTable.PSVersion -lt [version]'7.4') {
    throw 'Native bootstrap contract tests require PowerShell Core 7.4 or newer.'
}

$script:Passed = 0
$script:Failed = 0

function Assert-Contract {
    param(
        [Parameter(Mandatory)]
        [bool] $Condition,

        [Parameter(Mandatory)]
        [string] $Message
    )

    if ($Condition) {
        $script:Passed++
        Write-Host "PASS: $Message"
        return
    }

    $script:Failed++
    Write-Host "FAIL: $Message" -ForegroundColor Red
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$modulePath = Join-Path $repoRoot 'windows\NativeBootstrap.Contract.psm1'
$manifestPath = Join-Path $repoRoot 'windows\native-bootstrap.manifest.psd1'
$schemaPath = Join-Path $repoRoot 'windows\native-bootstrap-report.schema.json'

Assert-Contract -Condition (Test-Path -LiteralPath $modulePath -PathType Leaf) -Message 'the public contract module artifact exists'
Assert-Contract -Condition (Test-Path -LiteralPath $manifestPath -PathType Leaf) -Message 'the static manifest artifact exists'
Assert-Contract -Condition (Test-Path -LiteralPath $schemaPath -PathType Leaf) -Message 'the report schema artifact exists'

if ($script:Failed -gt 0) {
    Write-Host "Contract tests failed: $script:Failed failed, $script:Passed passed." -ForegroundColor Red
    exit 1
}

Write-Host "Contract tests passed: $script:Passed passed."
