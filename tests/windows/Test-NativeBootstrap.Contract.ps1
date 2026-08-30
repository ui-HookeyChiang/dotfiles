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

function Copy-ContractData {
    param([Parameter(Mandatory)] [object] $Value)
    return [Management.Automation.PSSerializer]::Deserialize([Management.Automation.PSSerializer]::Serialize($Value))
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
    $unknownField = Copy-ContractData $manifest
    $unknownField.unexpected = $true
    $invalidManifests += $unknownField
    $duplicateAction = Copy-ContractData $manifest
    $duplicateAction.projects[0].actions[0].id = $duplicateAction.actions[0].id
    $invalidManifests += $duplicateAction
    $duplicateDestination = Copy-ContractData $manifest
    $duplicateDestination.projects[1].destination_segment = 'DOTFILES'
    $invalidManifests += $duplicateDestination
    $unsafeExecutor = Copy-ContractData $manifest
    $unsafeExecutor.tools[0].executable = 'wsl.exe'
    $invalidManifests += $unsafeExecutor
    $contradictoryPolicy = Copy-ContractData $manifest
    $contradictoryPolicy.projects[0].actions[0].v1_state = 'inspect'
    $invalidManifests += $contradictoryPolicy
    $incompleteRecovery = Copy-ContractData $manifest
    $incompleteRecovery.actions[0].recovery.Remove('verification')
    $invalidManifests += $incompleteRecovery
    $unknownProfileField = Copy-ContractData $manifest
    $unknownProfileField.environment_profiles[0].unexpected = $true
    $invalidManifests += $unknownProfileField
    $missingProfileField = Copy-ContractData $manifest
    $missingProfileField.environment_profiles[0].Remove('allow_inherited')
    $invalidManifests += $missingProfileField
    $duplicateProfile = Copy-ContractData $manifest
    $duplicateProfile.environment_profiles[1].id = $duplicateProfile.environment_profiles[0].id
    $invalidManifests += $duplicateProfile
    $unknownProfileReference = Copy-ContractData $manifest
    $unknownProfileReference.tools[0].environment_profile = 'missing-profile'
    $invalidManifests += $unknownProfileReference
    $unknownWrapperField = Copy-ContractData $manifest
    $unknownWrapperField.tools[1].wrapper_policy.unexpected = $true
    $invalidManifests += $unknownWrapperField
    $missingWrapperField = Copy-ContractData $manifest
    $missingWrapperField.tools[1].wrapper_policy.Remove('require_sha256')
    $invalidManifests += $missingWrapperField
    $unknownFutureField = Copy-ContractData $manifest
    $unknownFutureField.future_activation.unexpected = $true
    $invalidManifests += $unknownFutureField
    $missingFutureField = Copy-ContractData $manifest
    $missingFutureField.future_activation.Remove('approve_all')
    $invalidManifests += $missingFutureField
    $wrongToolInventory = Copy-ContractData $manifest
    $wrongToolInventory.tools[0].executable = 'powershell.exe'
    $invalidManifests += $wrongToolInventory
    $brokenToolReference = Copy-ContractData $manifest
    $brokenToolReference.projects[0].required_tools[0] = 'missing-tool'
    $invalidManifests += $brokenToolReference
    $brokenPrerequisite = Copy-ContractData $manifest
    $brokenPrerequisite.projects[0].actions[1].prerequisites[0] = 'missing-action'
    $invalidManifests += $brokenPrerequisite
    $wrongProfileType = Copy-ContractData $manifest
    $wrongProfileType.environment_profiles[0].allow_inherited = 'false'
    $invalidManifests += $wrongProfileType
    $missingProjectField = Copy-ContractData $manifest
    $missingProjectField.projects[0].Remove('actions')
    $invalidManifests += $missingProjectField
    $missingActionField = Copy-ContractData $manifest
    $missingActionField.actions[0].Remove('executor_id')
    $invalidManifests += $missingActionField
    $missingToolField = Copy-ContractData $manifest
    $missingToolField.tools[0].Remove('network_policy')
    $invalidManifests += $missingToolField
    $nullTool = Copy-ContractData $manifest
    $nullTool.tools[0] = $null
    $invalidManifests += $nullTool
    $wrongProjectInventory = Copy-ContractData $manifest
    $wrongProjectInventory.projects[0].canonical_identity = 'github.com/ui-HookeyChiang/not-dotfiles'
    $invalidManifests += $wrongProjectInventory
    $wrongActionInventory = Copy-ContractData $manifest
    $wrongActionInventory.actions[0].id = 'replacement-action'
    $invalidManifests += $wrongActionInventory
    $unsafeToolArguments = Copy-ContractData $manifest
    $unsafeToolArguments.tools[0].version_argv = @('-EncodedCommand', 'arbitrary-code')
    $invalidManifests += $unsafeToolArguments
    $unsafeToolProfile = Copy-ContractData $manifest
    $unsafeToolProfile.tools[0].environment_profile = 'git-clone-gcm-future'
    $invalidManifests += $unsafeToolProfile
    $emptyProjectTools = Copy-ContractData $manifest
    $emptyProjectTools.projects[0].required_tools = @()
    $invalidManifests += $emptyProjectTools
    $emptyReadinessProbes = Copy-ContractData $manifest
    $emptyReadinessProbes.projects[0].readiness_probes = @()
    $invalidManifests += $emptyReadinessProbes
    $relocatedAction = Copy-ContractData $manifest
    $relocated = $relocatedAction.projects[0].actions[0]
    $relocatedAction.projects[0].actions = @($relocatedAction.projects[0].actions | Select-Object -Skip 1)
    $relocatedAction.actions = @($relocatedAction.actions) + @($relocated)
    $invalidManifests += $relocatedAction
    $optionalRequiredAction = Copy-ContractData $manifest
    $optionalRequiredAction.actions[0].required = $false
    $invalidManifests += $optionalRequiredAction
    $invalidRecoveryKind = Copy-ContractData $manifest
    $invalidRecoveryKind.actions[0].recovery.kind = 'bogus'
    $invalidManifests += $invalidRecoveryKind
    foreach ($invalidManifest in $invalidManifests) {
        $invalidResult = $null
        $threw = $false
        try { $invalidResult = Test-NativeBootstrapManifest -Manifest $invalidManifest } catch { $threw = $true }
        Assert-Contract -Condition (-not $threw -and -not $invalidResult.Valid -and $invalidResult.ExitCode -eq 30) -Message 'invalid contract data returns structured exit 30 without throwing or invoking a child seam'
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
    $optionalFailure = @(
        [pscustomobject]@{ required = $true; status = 'ready' },
        [pscustomobject]@{ required = $false; status = 'failed' }
    )
    Assert-Equal -Actual (Get-NativeBootstrapOverall -Results $optionalFailure) -Expected 'ready' -Message 'optional failures do not escalate a required ready result'
    Assert-Equal -Actual (Get-NativeBootstrapOverall -Results @([pscustomobject]@{ required = $false; status = 'failed' })) -Expected 'skipped' -Message 'optional-only results do not define overall status'
    Assert-Equal -Actual (Get-NativeBootstrapExitCode -Overall ready -Manifest $manifest -Results @() -Plans @()) -Expected 10 -Message 'exit selection derives required deferred work from the manifest'
    $requiredBlockedPlan = @([pscustomobject]@{ required = $true; state = 'blocked'; blocked_by = @('deferred') })
    Assert-Equal -Actual (Get-NativeBootstrapExitCode -Overall ready -Results @() -Plans $requiredBlockedPlan) -Expected 10 -Message 'exit selection derives required blocking from plans'
    $requiredDeferredPlan = @([pscustomobject]@{ required = $true; state = 'planned'; recovery = [pscustomobject]@{ kind = 'deferred' } })
    Assert-Equal -Actual (Get-NativeBootstrapExitCode -Overall ready -Results @() -Plans $requiredDeferredPlan) -Expected 10 -Message 'exit selection derives required deferred recovery from plans'
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
    foreach ($secretText in @('TOKEN="two words" trailing', "PASSWORD='two words' trailing", 'API_KEY="escaped \"value\" here" trailing', 'SECRET="unterminated value')) {
        $quotedRedaction = Protect-NativeBootstrapText -Text $secretText
        Assert-Contract -Condition ($quotedRedaction -notmatch 'two words|escaped|value|here' -and $quotedRedaction -match '<redacted>') -Message 'quoted credential assignments are redacted through their closing quote'
    }
    foreach ($secretText in @('AWS_ACCESS_KEY_ID=AKIAEXAMPLE', 'PRIVATE_KEY=private-material', "SECRET=`"first`r`nsecond-secret")) {
        $keyRedaction = Protect-NativeBootstrapText -Text $secretText
        Assert-Contract -Condition ($keyRedaction -notmatch 'AKIAEXAMPLE|private-material|second-secret' -and $keyRedaction -match '<redacted>') -Message 'generic key names and multiline unterminated quoted credentials are redacted'
    }

    $fullFixture = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'fixtures\native-bootstrap-report\valid\full.json') | ConvertFrom-Json
    $serialized = ConvertTo-NativeBootstrapReportJson -Report $fullFixture
    Assert-Contract -Condition ($serialized.StartsWith('{"schema_version":1,"report_kind":"full","command":"check","execution_provenance":"windows-native","check_contract_ready":true')) -Message 'full report serialization uses the fixed canonical field order'
    Assert-Contract -Condition ($serialized | Test-Json -SchemaFile $schemaPath) -Message 'serialized full reports satisfy the native JSON Schema contract'
    $orderedReportA = $fullFixture
    $orderedReportB = $fullFixture | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $orderedReportA.plans[0].blocked_by = @('zeta', 'alpha')
    $orderedReportA.plans[0].prerequisites = @('tool.z', 'tool.a')
    $orderedReportB.plans[0].blocked_by = @('alpha', 'zeta')
    $orderedReportB.plans[0].prerequisites = @('tool.a', 'tool.z')
    $orderedReportA.results = @(
        [pscustomobject][ordered]@{ scope = 'action'; name = 'z'; required = $true; status = 'action_required'; code = 'NPR-Z'; message = 'z'; remediation = $null },
        [pscustomobject][ordered]@{ scope = 'host'; name = 'host'; required = $true; status = 'ready'; code = 'NPR-A'; message = 'a'; remediation = $null }
    )
    $orderedReportB.results = @(
        [pscustomobject]@{ remediation = $null; message = 'a'; code = 'NPR-A'; status = 'ready'; required = $true; name = 'host'; scope = 'host' },
        [pscustomobject]@{ remediation = $null; message = 'z'; code = 'NPR-Z'; status = 'action_required'; required = $true; name = 'z'; scope = 'action' }
    )
    Assert-Equal -Actual (ConvertTo-NativeBootstrapReportJson -Report $orderedReportA) -Expected (ConvertTo-NativeBootstrapReportJson -Report $orderedReportB) -Message 'canonical serialization is byte-identical across nested dictionary and set ordering'
    $canonicalOrderReport = $fullFixture | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $canonicalOrderReport.plans = @(
        [pscustomobject]@{ action_id = 'services.deferred'; target = 'host'; required = $true; state = 'blocked'; blocked_by = @('ä', 'z', 'a'); prerequisites = @(); credential_policy = 'deny'; network_policy = 'deny'; environment_profile = 'tool-probe-v1'; recovery = [pscustomobject]@{ kind = 'deferred'; owner = 'issue 09'; affected = @(); instructions = 'deferred'; verification = 'verify' } },
        [pscustomobject]@{ action_id = 'shell-tests.deferred'; target = 'host'; required = $true; state = 'blocked'; blocked_by = @('deferred'); prerequisites = @(); credential_policy = 'deny'; network_policy = 'deny'; environment_profile = 'tool-probe-v1'; recovery = [pscustomobject]@{ kind = 'deferred'; owner = 'issue 08'; affected = @(); instructions = 'deferred'; verification = 'verify' } }
    )
    $canonicalOrderReport.results = @(
        [pscustomobject]@{ scope = 'action'; name = 'services.deferred'; required = $true; status = 'action_required'; code = 'NPR-SERVICE'; message = 'service'; remediation = $null },
        [pscustomobject]@{ scope = 'host'; name = 'host'; required = $true; status = 'ready'; code = 'NPR-HOST'; message = 'host'; remediation = $null }
    )
    $canonicalOrder = ConvertTo-NativeBootstrapReportJson -Report $canonicalOrderReport | ConvertFrom-Json
    Assert-Equal -Actual @($canonicalOrder.plans.action_id) -Expected @('shell-tests.deferred', 'services.deferred') -Message 'canonical plans follow manifest action order'
    Assert-Equal -Actual @($canonicalOrder.results.scope) -Expected @('host', 'action') -Message 'canonical results put host scope first'
    Assert-Equal -Actual @($canonicalOrder.plans[1].blocked_by) -Expected @('a', 'z', 'ä') -Message 'canonical sets use ordinal string order'

    $readyWithBlockedPlan = $fullFixture | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $readyWithBlockedPlan.overall = 'ready'
    $readyWithBlockedPlan.exit_code = 0
    $readyWithBlockedPlan.plans[0].state = 'planned'
    $readyBlockedValid = $false
    try { $readyBlockedValid = ($readyWithBlockedPlan | ConvertTo-Json -Depth 30) | Test-Json -SchemaFile $schemaPath -ErrorAction Stop } catch { $readyBlockedValid = $false }
    Assert-Contract -Condition (-not $readyBlockedValid) -Message 'schema rejects ready exit 0 with a required blocked plan'
    $readyWithoutPlans = $fullFixture | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $readyWithoutPlans.plans = @()
    $readyWithoutPlans.overall = 'ready'
    $readyWithoutPlans.exit_code = 0
    $readyWithoutPlansValid = $false
    try { $readyWithoutPlansValid = ($readyWithoutPlans | ConvertTo-Json -Depth 30) | Test-Json -SchemaFile $schemaPath -ErrorAction Stop } catch { $readyWithoutPlansValid = $false }
    Assert-Contract -Condition (-not $readyWithoutPlansValid) -Message 'schema version 1 rejects ready exit 0 even when required plans are omitted'
    $readyWithoutPlans.check_contract_ready = $false
    $readyWithoutPlansValid = $false
    try { $readyWithoutPlansValid = ($readyWithoutPlans | ConvertTo-Json -Depth 30) | Test-Json -SchemaFile $schemaPath -ErrorAction Stop } catch { $readyWithoutPlansValid = $false }
    Assert-Contract -Condition (-not $readyWithoutPlansValid) -Message 'schema version 1 rejects exit 0 before contract readiness completes'

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
    $coveredMutationStates = @(Get-ChildItem -LiteralPath (Join-Path $fixtureRoot 'valid') -Filter '*.json' | ForEach-Object {
        $fixtureData = Get-Content -Raw -LiteralPath $_.FullName | ConvertFrom-Json
        if ($null -ne $fixtureData.PSObject.Properties['mutations']) {
            foreach ($mutation in @($fixtureData.mutations)) { if ($null -ne $mutation) { $mutation.state } }
        }
    } | Sort-Object -Unique)
    Assert-Equal -Actual $coveredMutationStates -Expected @('applied', 'failed', 'partial', 'unknown') -Message 'valid pure fixtures cover every successor mutation terminal state'
    $coveredDiagnostics = @(Get-ChildItem -LiteralPath (Join-Path $fixtureRoot 'valid') -Filter '*.json' | ForEach-Object {
        $fixtureData = Get-Content -Raw -LiteralPath $_.FullName | ConvertFrom-Json
        if ($null -ne $fixtureData.PSObject.Properties['diagnostics']) { $fixtureData.diagnostics }
    } | Where-Object { $null -ne $_ })
    Assert-Contract -Condition ($coveredDiagnostics.Count -gt 0) -Message 'valid pure fixtures exercise non-empty diagnostic objects'
}

if ($script:Failed -gt 0) {
    Write-Host "Contract tests failed: $script:Failed failed, $script:Passed passed." -ForegroundColor Red
    exit 1
}

Write-Host "Contract tests passed: $script:Passed passed."
