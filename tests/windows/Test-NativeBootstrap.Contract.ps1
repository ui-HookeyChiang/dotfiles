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

function Assert-Equal {
    param(
        [AllowNull()]
        [object] $Actual,

        [AllowNull()]
        [object] $Expected,

        [Parameter(Mandatory)]
        [string] $Message
    )

    Assert-Contract -Condition (($Actual | ConvertTo-Json -Depth 20 -Compress) -ceq ($Expected | ConvertTo-Json -Depth 20 -Compress)) -Message $Message
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$modulePath = Join-Path $repoRoot 'windows\NativeBootstrap.Contract.psm1'
$manifestPath = Join-Path $repoRoot 'windows\native-bootstrap.manifest.psd1'
$schemaPath = Join-Path $repoRoot 'windows\native-bootstrap-report.schema.json'

Assert-Contract -Condition (Test-Path -LiteralPath $modulePath -PathType Leaf) -Message 'the public contract module artifact exists'
Assert-Contract -Condition (Test-Path -LiteralPath $manifestPath -PathType Leaf) -Message 'the static manifest artifact exists'
Assert-Contract -Condition (Test-Path -LiteralPath $schemaPath -PathType Leaf) -Message 'the report schema artifact exists'

if ($script:Failed -eq 0) {
    $manifest = Import-PowerShellDataFile -LiteralPath $manifestPath
    Assert-Equal -Actual $manifest.schema_version -Expected 1 -Message 'the manifest uses schema version 1'
    Assert-Equal -Actual @($manifest.projects | ForEach-Object { $_.name }) -Expected @('dotfiles', 'skill-dev', 'Awesome-CV', 'telegram-claude-bridge', 'stock-target-finder') -Message 'the manifest contains the five projects in canonical order'
    Assert-Equal -Actual @($manifest.tools | ForEach-Object { $_.id }) -Expected @('pwsh', 'scoop', 'git', 'gh', 'node', 'npm', 'python', 'uv', 'jq', 'yq', 'fzf', 'fd', 'ast-grep', 'pdfinfo', 'xelatex') -Message 'the manifest declares every version 1 tool descriptor'
    Assert-Equal -Actual @($manifest.actions | ForEach-Object { $_.id }) -Expected @('checkout-root.create.deferred', 'shell-tests.deferred', 'services.deferred') -Message 'the manifest declares required host-level deferred records'
}

if ($script:Failed -eq 0) {
    Import-Module -Name $modulePath -Force

    $validation = Test-NativeBootstrapManifest -Manifest $manifest
    Assert-Contract -Condition $validation.Valid -Message 'the canonical manifest passes pure invariant validation'
    Assert-Equal -Actual $validation.ExitCode -Expected 0 -Message 'valid contract data maps to exit 0 from the validator'

    $invalidManifests = @()
    $unknownField = [Management.Automation.PSSerializer]::Deserialize([Management.Automation.PSSerializer]::Serialize($manifest))
    $unknownField.unexpected = $true
    $invalidManifests += $unknownField
    $duplicateAction = [Management.Automation.PSSerializer]::Deserialize([Management.Automation.PSSerializer]::Serialize($manifest))
    $duplicateAction.projects[0].actions[0].id = $duplicateAction.actions[0].id
    $invalidManifests += $duplicateAction
    $duplicateDestination = [Management.Automation.PSSerializer]::Deserialize([Management.Automation.PSSerializer]::Serialize($manifest))
    $duplicateDestination.projects[1].destination_segment = 'DOTFILES'
    $invalidManifests += $duplicateDestination
    $unsafeExecutor = [Management.Automation.PSSerializer]::Deserialize([Management.Automation.PSSerializer]::Serialize($manifest))
    $unsafeExecutor.tools[0].executable = 'wsl.exe'
    $invalidManifests += $unsafeExecutor
    $contradictoryPolicy = [Management.Automation.PSSerializer]::Deserialize([Management.Automation.PSSerializer]::Serialize($manifest))
    $contradictoryPolicy.projects[0].actions[0].v1_state = 'inspect'
    $invalidManifests += $contradictoryPolicy
    $incompleteRecovery = [Management.Automation.PSSerializer]::Deserialize([Management.Automation.PSSerializer]::Serialize($manifest))
    $incompleteRecovery.actions[0].recovery.Remove('verification')
    $invalidManifests += $incompleteRecovery
    foreach ($invalidManifest in $invalidManifests) {
        $invalidResult = Test-NativeBootstrapManifest -Manifest $invalidManifest
        Assert-Contract -Condition (-not $invalidResult.Valid -and $invalidResult.ExitCode -eq 30) -Message 'invalid contract data is rejected and maps to exit 30 without a child seam'
    }

    foreach ($url in @('git@github.com:UI-HookeyChiang/DotFiles.git', 'ssh://git@github.com/ui-HookeyChiang/dotfiles.git', 'https://github.com/ui-HookeyChiang/dotfiles.git')) {
        Assert-Equal -Actual (ConvertTo-NativeBootstrapIdentity -Url $url) -Expected 'github.com/ui-hookeychiang/dotfiles' -Message "accepted GitHub URL normalizes: $url"
    }
    foreach ($url in @('https://user:secret@github.com/o/r.git', 'https://example.com/o/r.git', 'https://github.com/o/r/extra', 'https://github.com/o/r.git?x=1', 'file:///D:/repo', 'D:\repo')) {
        Assert-Equal -Actual (ConvertTo-NativeBootstrapIdentity -Url $url) -Expected $null -Message "unsafe or noncanonical URL is rejected: $url"
    }

    Assert-Contract -Condition (Test-NativeBootstrapTransition -From planned -To blocked) -Message 'planned actions may become blocked'
    Assert-Contract -Condition (Test-NativeBootstrapTransition -From started -To partial) -Message 'started actions may become partial'
    Assert-Contract -Condition (-not (Test-NativeBootstrapTransition -From planned -To applied)) -Message 'actions cannot skip authorization and start states'
    Assert-Contract -Condition (-not (Test-NativeBootstrapTransition -From applied -To started)) -Message 'terminal action states cannot transition'

    $results = @(
        [pscustomobject]@{ scope = 'repository'; name = 'skill-dev'; required = $false; status = 'warning'; code = 'NPR-Z' },
        [pscustomobject]@{ scope = 'host'; name = 'host'; required = $true; status = 'ready'; code = 'NPR-HOST' },
        [pscustomobject]@{ scope = 'repository'; name = 'dotfiles'; required = $true; status = 'skipped'; code = 'NPR-A' }
    )
    Assert-Equal -Actual (Get-NativeBootstrapOverall -Results $results) -Expected 'action_required' -Message 'required skipped results normalize to action-required with fixed precedence'
    Assert-Equal -Actual (Get-NativeBootstrapExitCode -Overall ready -RequiredDeferred) -Expected 10 -Message 'exit 0 is unreachable while required deferred work exists'
    Assert-Equal -Actual (Get-NativeBootstrapExitCode -Overall failed) -Expected 20 -Message 'failed operations select exit 20'
    Assert-Equal -Actual (Get-NativeBootstrapExitCode -Overall ready -InvariantFailure) -Expected 30 -Message 'invariant failure selects exit 30'
    $sorted = Sort-NativeBootstrapResults -Results $results -ProjectOrder @('dotfiles', 'skill-dev')
    Assert-Equal -Actual @($sorted | ForEach-Object { $_.code }) -Expected @('NPR-HOST', 'NPR-A', 'NPR-Z') -Message 'canonical result ordering puts host first and follows project order'

    $profileA = [ordered]@{ id = 'p'; allowed = @('z', 'a'); fixed = @{ B = '2'; A = '1' } }
    $profileB = [ordered]@{ fixed = @{ A = '1'; B = '2' }; allowed = @('a', 'z'); id = 'p' }
    Assert-Equal -Actual (Get-NativeBootstrapEnvironmentProfileHash -Profile $profileA) -Expected (Get-NativeBootstrapEnvironmentProfileHash -Profile $profileB) -Message 'environment profile hashing is canonical across key and set order'
    $redacted = Protect-NativeBootstrapText -Text "TOKEN=hunter2 Authorization: Bearer abc https://user:pass@example.com/a C:\Users\Ada\secret`u{0001}" -ProfileRoots @('C:\Users\Ada')
    Assert-Contract -Condition ($redacted -notmatch 'hunter2|abc|user:pass|C:\\Users\\Ada' -and $redacted -match '<redacted>' -and $redacted -match '<profile-root>') -Message 'diagnostic text redacts credential forms, URL userinfo, profile roots, and controls'
    Assert-Equal -Actual (Protect-NativeBootstrapText -Text 'anything' -CredentialAuthorized) -Expected '<suppressed:credential-authorized-action>' -Message 'credential-authorized child text is fully suppressed'

    $fullFixture = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'fixtures\native-bootstrap-report\valid\full.json') | ConvertFrom-Json
    $serialized = ConvertTo-NativeBootstrapReportJson -Report $fullFixture
    Assert-Contract -Condition ($serialized.StartsWith('{"schema_version":1,"report_kind":"full","command":"check","execution_provenance":"windows-native","check_contract_ready":true')) -Message 'full report serialization uses the fixed canonical field order'
    Assert-Contract -Condition ($serialized | Test-Json -SchemaFile $schemaPath) -Message 'serialized full reports satisfy the native JSON Schema contract'

    $fixtureRoot = Join-Path $PSScriptRoot 'fixtures\native-bootstrap-report'
    foreach ($fixture in Get-ChildItem -LiteralPath (Join-Path $fixtureRoot 'valid') -Filter '*.json' | Sort-Object Name) {
        $fixtureJson = Get-Content -Raw -LiteralPath $fixture.FullName
        $isValid = $fixtureJson | Test-Json -SchemaFile $schemaPath
        Assert-Contract -Condition $isValid -Message "valid schema fixture is accepted by Test-Json: $($fixture.Name)"
        $reserialized = ConvertTo-NativeBootstrapReportJson -Report ($fixtureJson | ConvertFrom-Json)
        Assert-Contract -Condition ($reserialized | Test-Json -SchemaFile $schemaPath) -Message "valid schema fixture survives canonical serialization: $($fixture.Name)"
    }
    foreach ($fixture in Get-ChildItem -LiteralPath (Join-Path $fixtureRoot 'invalid') -Filter '*.json' | Sort-Object Name) {
        $isValid = $false
        try { $isValid = Get-Content -Raw -LiteralPath $fixture.FullName | Test-Json -SchemaFile $schemaPath -ErrorAction Stop } catch { $isValid = $false }
        Assert-Contract -Condition (-not $isValid) -Message "invalid schema fixture is rejected by Test-Json: $($fixture.Name)"
    }
}

if ($script:Failed -gt 0) {
    Write-Host "Contract tests failed: $script:Failed failed, $script:Passed passed." -ForegroundColor Red
    exit 1
}

Write-Host "Contract tests passed: $script:Passed passed."
