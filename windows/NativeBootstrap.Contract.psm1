Set-StrictMode -Version Latest

function Get-ContractKeys {
    param([Parameter(Mandatory)] [object] $Value)
    if ($Value -is [System.Collections.IDictionary]) { return @($Value.Keys) }
    return @($Value.PSObject.Properties.Name)
}

function Get-ContractValue {
    param([Parameter(Mandatory)] [object] $Value, [Parameter(Mandatory)] [string] $Name)
    if ($Value -is [System.Collections.IDictionary]) { return $Value[$Name] }
    $property = $Value.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Test-ContractFields {
    param([object] $Value, [string[]] $Required, [string[]] $Allowed, [string] $Location, [System.Collections.Generic.List[string]] $Errors)
    if ($null -eq $Value) { $Errors.Add("$Location is missing."); return }
    $keys = @(Get-ContractKeys $Value)
    foreach ($name in $Required) { if ($name -notin $keys) { $Errors.Add("$Location is missing field '$name'.") } }
    foreach ($name in $keys) { if ($name -notin $Allowed) { $Errors.Add("$Location has unknown field '$name'.") } }
}

function Test-NativeBootstrapManifest {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [object] $Manifest)

    $errors = [System.Collections.Generic.List[string]]::new()
    $topFields = @('schema_version', 'environment_profiles', 'tools', 'actions', 'projects', 'future_activation')
    Test-ContractFields $Manifest $topFields $topFields 'manifest' $errors
    if ($errors.Count -eq 0 -and (Get-ContractValue $Manifest 'schema_version') -ne 1) { $errors.Add('manifest.schema_version must equal 1.') }

    $projectFields = @('name', 'destination_segment', 'canonical_identity', 'clone_url', 'required_tools', 'readiness_probes', 'actions')
    $toolFields = @('id', 'executable', 'resolver_roots', 'version_argv', 'version_parser', 'version_constraint', 'required_projects', 'environment_profile', 'timeout_seconds', 'network_policy', 'remediation', 'wrapper_policy')
    $actionFields = @('id', 'phase', 'kind', 'executor_id', 'argv_template', 'working_directory', 'checkout_effect', 'credential_policy', 'network_policy', 'dirty_policy', 'required', 'v1_state', 'prerequisites', 'success_probe', 'recovery')
    $recoveryFields = @('kind', 'owner', 'affected', 'instructions', 'verification')
    $projects = @((Get-ContractValue $Manifest 'projects'))
    $tools = @((Get-ContractValue $Manifest 'tools'))
    $hostActions = @((Get-ContractValue $Manifest 'actions'))
    $profiles = @((Get-ContractValue $Manifest 'environment_profiles'))

    foreach ($index in 0..([Math]::Max(0, $projects.Count - 1))) {
        if ($projects.Count -eq 0) { break }
        Test-ContractFields $projects[$index] $projectFields $projectFields "projects[$index]" $errors
    }
    foreach ($index in 0..([Math]::Max(0, $tools.Count - 1))) {
        if ($tools.Count -eq 0) { break }
        Test-ContractFields $tools[$index] $toolFields $toolFields "tools[$index]" $errors
    }

    $allActions = [System.Collections.Generic.List[object]]::new()
    foreach ($action in $hostActions) { $allActions.Add($action) }
    foreach ($project in $projects) { foreach ($action in @($project.actions)) { $allActions.Add($action) } }
    foreach ($index in 0..([Math]::Max(0, $allActions.Count - 1))) {
        if ($allActions.Count -eq 0) { break }
        $action = $allActions[$index]
        Test-ContractFields $action $actionFields $actionFields "actions[$index]" $errors
        if (@(Get-ContractKeys $action) -contains 'recovery') { Test-ContractFields $action.recovery $recoveryFields $recoveryFields "actions[$index].recovery" $errors }
    }

    $projectNames = @($projects | ForEach-Object { $_.name })
    if ($projects.Count -ne 5) { $errors.Add('manifest must contain exactly five projects.') }
    if ((@($projectNames | Sort-Object -Unique).Count) -ne $projectNames.Count) { $errors.Add('project names must be unique.') }
    $destinations = @($projects | ForEach-Object { [string]$_.destination_segment } | ForEach-Object { $_.ToLowerInvariant() })
    if ((@($destinations | Sort-Object -Unique).Count) -ne $destinations.Count) { $errors.Add('project destinations must be unique ignoring case.') }
    $toolIds = @($tools | ForEach-Object { $_.id })
    if ((@($toolIds | Sort-Object -Unique).Count) -ne $toolIds.Count) { $errors.Add('tool IDs must be unique.') }
    $profileIds = @($profiles | ForEach-Object { $_.id })
    $actionIds = @($allActions | ForEach-Object { $_.id })
    if ((@($actionIds | Sort-Object -Unique).Count) -ne $actionIds.Count) { $errors.Add('action IDs must be globally unique.') }

    foreach ($tool in $tools) {
        if ($tool.environment_profile -notin $profileIds) { $errors.Add("tool '$($tool.id)' references an unknown environment profile.") }
        if ($tool.network_policy -ne 'deny' -or $tool.timeout_seconds -le 0) { $errors.Add("tool '$($tool.id)' has an unsafe probe policy.") }
        if ($tool.executable -match '(?i)^(wsl|bash)(\.exe)?$') { $errors.Add("tool '$($tool.id)' uses an unsafe executor.") }
    }
    foreach ($action in $allActions) {
        $id = Get-ContractValue $action 'id'
        $executorId = Get-ContractValue $action 'executor_id'
        $effect = Get-ContractValue $action 'checkout_effect'
        $state = Get-ContractValue $action 'v1_state'
        $dirtyPolicy = Get-ContractValue $action 'dirty_policy'
        $credentialPolicy = Get-ContractValue $action 'credential_policy'
        $networkPolicy = Get-ContractValue $action 'network_policy'
        $required = Get-ContractValue $action 'required'
        $recovery = Get-ContractValue $action 'recovery'
        if ($executorId -ne 'none' -and $executorId -notin $toolIds) { $errors.Add("action '$id' references an unknown executor.") }
        if ($effect -notin @('inspect', 'execute', 'install', 'copy', 'configure')) { $errors.Add("action '$id' has an invalid checkout effect.") }
        if ($effect -ne 'inspect' -and ($state -ne 'deferred' -or $dirtyPolicy -ne 'require-clean')) { $errors.Add("action '$id' has a contradictory version 1 policy.") }
        if ($state -notin @('deferred', 'inspect')) { $errors.Add("action '$id' has an invalid version 1 state.") }
        if ($credentialPolicy -notin @('deny', 'required', 'optional') -or $networkPolicy -notin @('deny', 'required', 'optional')) { $errors.Add("action '$id' has an invalid policy.") }
        $recoveryKind = if ($null -eq $recovery) { $null } else { Get-ContractValue $recovery 'kind' }
        if ($required -and $recoveryKind -eq 'deferred' -and $state -ne 'deferred') { $errors.Add("action '$id' cannot execute with deferred recovery.") }
        $owner = if ($null -eq $recovery) { $null } else { Get-ContractValue $recovery 'owner' }
        $instructions = if ($null -eq $recovery) { $null } else { Get-ContractValue $recovery 'instructions' }
        $verification = if ($null -eq $recovery) { $null } else { Get-ContractValue $recovery 'verification' }
        if ([string]::IsNullOrWhiteSpace([string]$owner) -or [string]::IsNullOrWhiteSpace([string]$instructions) -or [string]::IsNullOrWhiteSpace([string]$verification)) { $errors.Add("action '$id' has incomplete recovery.") }
    }

    [pscustomobject][ordered]@{ Valid = ($errors.Count -eq 0); ExitCode = $(if ($errors.Count -eq 0) { 0 } else { 30 }); Errors = @($errors) }
}

function ConvertTo-NativeBootstrapIdentity {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Url)

    if ($Url -match '[?#]' -or $Url -match '^[a-zA-Z]:[\\/]' -or $Url -match '^(?i:file)://') { return $null }
    $candidate = $Url.Trim()
    if ($candidate -match '^git@github\.com:([^/]+)/([^/]+)$') { $owner = $Matches[1]; $repo = $Matches[2] }
    elseif ($candidate -match '^(?i:ssh)://git@github\.com/([^/]+)/([^/]+)$') { $owner = $Matches[1]; $repo = $Matches[2] }
    elseif ($candidate -match '^(?i:https)://github\.com/([^/]+)/([^/]+)$') { $owner = $Matches[1]; $repo = $Matches[2] }
    else { return $null }
    $repo = $repo -replace '\.git$', ''
    if ([string]::IsNullOrWhiteSpace($owner) -or [string]::IsNullOrWhiteSpace($repo) -or $owner.Contains('@') -or $repo.Contains('/')) { return $null }
    return "github.com/$($owner.ToLowerInvariant())/$($repo.ToLowerInvariant())"
}

function Test-NativeBootstrapTransition {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $From, [Parameter(Mandatory)] [string] $To)
    $allowed = @{
        planned = @('blocked', 'authorized')
        authorized = @('started')
        started = @('applied', 'failed', 'partial', 'unknown')
        blocked = @(); applied = @(); failed = @(); partial = @(); unknown = @()
    }
    return $allowed.ContainsKey($From) -and $To -in $allowed[$From]
}

function Get-NativeBootstrapOverall {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [object[]] $Results)
    $rank = @{ skipped = 0; ready = 1; warning = 2; action_required = 3; failed = 4 }
    $winner = 'skipped'
    foreach ($result in $Results) {
        $status = [string]$result.status
        if ($result.required -and $status -eq 'skipped') { $status = 'action_required' }
        if ($rank[$status] -gt $rank[$winner]) { $winner = $status }
    }
    return $winner
}

function Get-NativeBootstrapExitCode {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Overall, [switch] $InvocationError, [switch] $InvariantFailure, [switch] $RequiredDeferred)
    if ($InvariantFailure) { return 30 }
    if ($InvocationError) { return 2 }
    if ($Overall -eq 'failed') { return 20 }
    if ($RequiredDeferred -or $Overall -eq 'action_required') { return 10 }
    if ($Overall -in @('ready', 'warning', 'skipped')) { return 0 }
    throw "Unknown overall status '$Overall'."
}

function Sort-NativeBootstrapResults {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [object[]] $Results, [Parameter(Mandatory)] [string[]] $ProjectOrder)
    $scopeRank = @{ host = 0; tool = 1; repository = 2; action = 3; service = 4 }
    return @($Results | Sort-Object @{ Expression = { if ($_.scope -in @('host', 'tool')) { 0 } else { 1 } } }, @{ Expression = { $position = [Array]::IndexOf($ProjectOrder, [string]$_.name); if ($position -lt 0) { [int]::MaxValue } else { $position } } }, @{ Expression = { $scopeRank[[string]$_.scope] } }, @{ Expression = { [string]$_.code } })
}

function Get-NativeBootstrapEnvironmentProfileHash {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [object] $Profile)
    $pairs = foreach ($key in @(Get-ContractKeys $Profile | Sort-Object)) {
        $value = Get-ContractValue $Profile $key
        if ($value -is [System.Collections.IDictionary]) { $encoded = (@(Get-ContractKeys $value | Sort-Object | ForEach-Object { "$_=$($value[$_])" }) -join ',') }
        elseif ($value -is [array]) { $encoded = (@($value | Sort-Object) -join ',') }
        else { $encoded = [string]$value }
        "$key=$encoded"
    }
    $bytes = [Text.Encoding]::UTF8.GetBytes(($pairs -join "`n"))
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}

function Protect-NativeBootstrapText {
    [CmdletBinding()]
    param([AllowNull()] [string] $Text, [switch] $CredentialAuthorized, [string[]] $ProfileRoots = @())
    if ($CredentialAuthorized) { return '<suppressed:credential-authorized-action>' }
    if ($null -eq $Text) { return $null }
    $result = $Text -replace '(?i)(authorization\s*:\s*(?:bearer|basic)\s+)\S+', '$1<redacted>'
    $result = $result -replace '(?i)\b([A-Z0-9_]*(?:TOKEN|SECRET|PASSWORD|CREDENTIAL|API_KEY)[A-Z0-9_]*)\s*=\s*\S+', '$1=<redacted>'
    $result = $result -replace '(?i)(https?://)[^/@\s]+@', '$1<redacted>@'
    foreach ($root in $ProfileRoots) { if (-not [string]::IsNullOrWhiteSpace($root)) { $result = $result.Replace($root, '<profile-root>', [StringComparison]::OrdinalIgnoreCase) } }
    return [regex]::Replace($result, '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]', { param($match) "\u$([int][char]$match.Value).ToString('x4')" })
}

function ConvertTo-NativeBootstrapReportJson {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [object] $Report)
    $order = @('schema_version', 'report_kind', 'command', 'execution_provenance', 'check_contract_ready', 'projects_dir', 'offline', 'overall', 'exit_code', 'authorizations', 'plans', 'results', 'mutations', 'diagnostics', 'errors', 'fallback')
    $output = [ordered]@{}
    foreach ($name in $order) {
        if ($name -notin @(Get-ContractKeys $Report)) { continue }
        if ($Report -is [System.Collections.IDictionary]) { $output[$name] = $Report[$name] }
        else { $output[$name] = $Report.PSObject.Properties[$name].Value }
    }
    return ($output | ConvertTo-Json -Depth 30 -Compress)
}

Export-ModuleMember -Function @(
    'Test-NativeBootstrapManifest',
    'ConvertTo-NativeBootstrapIdentity',
    'Test-NativeBootstrapTransition',
    'Get-NativeBootstrapOverall',
    'Get-NativeBootstrapExitCode',
    'Sort-NativeBootstrapResults',
    'Get-NativeBootstrapEnvironmentProfileHash',
    'Protect-NativeBootstrapText',
    'ConvertTo-NativeBootstrapReportJson'
)
