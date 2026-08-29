Set-StrictMode -Version Latest

function Get-ContractKeys {
    param([Parameter(Mandatory)] [AllowNull()] [object] $Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Collections.IDictionary]) { return @($Value.Keys) }
    return @($Value.PSObject.Properties.Name)
}

function Get-ContractValue {
    param([Parameter(Mandatory)] [AllowNull()] [object] $Value, [Parameter(Mandatory)] [string] $Name)
    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Collections.IDictionary]) { $result = $Value[$Name] }
    else {
        $property = $Value.PSObject.Properties[$Name]
        if ($null -eq $property) { return $null }
        $result = $property.Value
    }
    if ($result -is [array]) { return ,$result }
    return $result
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
    param([Parameter(Mandatory)] [AllowNull()] [object] $Manifest)

    $errors = [System.Collections.Generic.List[string]]::new()
    $topFields = @('schema_version', 'environment_profiles', 'tools', 'actions', 'projects', 'future_activation')
    Test-ContractFields $Manifest $topFields $topFields 'manifest' $errors
    if ($errors.Count -eq 0 -and (Get-ContractValue $Manifest 'schema_version') -ne 1) { $errors.Add('manifest.schema_version must equal 1.') }

    $projectFields = @('name', 'destination_segment', 'canonical_identity', 'clone_url', 'required_tools', 'readiness_probes', 'actions')
    $toolFields = @('id', 'executable', 'resolver_roots', 'version_argv', 'version_parser', 'version_constraint', 'required_projects', 'environment_profile', 'timeout_seconds', 'network_policy', 'remediation', 'wrapper_policy')
    $actionFields = @('id', 'phase', 'kind', 'executor_id', 'argv_template', 'working_directory', 'checkout_effect', 'credential_policy', 'network_policy', 'dirty_policy', 'required', 'v1_state', 'prerequisites', 'success_probe', 'recovery')
    $recoveryFields = @('kind', 'owner', 'affected', 'instructions', 'verification')
    $profileFields = @('id', 'schema_version', 'allowed_inputs', 'fixed_values', 'denied_name_patterns', 'credential_policy', 'network_policy', 'allow_inherited')
    $wrapperFields = @('host_executable', 'require_absolute_path', 'require_non_reparse', 'require_sha256', 'reviewed_content_required', 'fixed_arguments_only')
    $futureFields = @('available_in_v1', 'approval_scope', 'approve_all', 'force', 'inherited_environment', 'credential_authorization', 'required_descriptor_fields', 'revalidate_immediately_before_spawn')
    $projects = @((Get-ContractValue $Manifest 'projects'))
    $tools = @((Get-ContractValue $Manifest 'tools'))
    $hostActions = @((Get-ContractValue $Manifest 'actions'))
    $profiles = @((Get-ContractValue $Manifest 'environment_profiles'))
    $future = Get-ContractValue $Manifest 'future_activation'

    foreach ($index in 0..([Math]::Max(0, $projects.Count - 1))) {
        if ($projects.Count -eq 0) { break }
        Test-ContractFields $projects[$index] $projectFields $projectFields "projects[$index]" $errors
    }
    foreach ($index in 0..([Math]::Max(0, $tools.Count - 1))) {
        if ($tools.Count -eq 0) { break }
        Test-ContractFields $tools[$index] $toolFields $toolFields "tools[$index]" $errors
        if ($null -eq $tools[$index]) { continue }
        $wrapper = Get-ContractValue $tools[$index] 'wrapper_policy'
        if ($null -ne $wrapper) { Test-ContractFields $wrapper $wrapperFields $wrapperFields "tools[$index].wrapper_policy" $errors }
    }
    foreach ($index in 0..([Math]::Max(0, $profiles.Count - 1))) {
        if ($profiles.Count -eq 0) { break }
        Test-ContractFields $profiles[$index] $profileFields $profileFields "environment_profiles[$index]" $errors
    }
    Test-ContractFields $future $futureFields $futureFields 'future_activation' $errors

    $allActions = [System.Collections.Generic.List[object]]::new()
    foreach ($action in $hostActions) { if ($null -ne $action) { $allActions.Add($action) } }
    foreach ($project in $projects) {
        if ($null -eq $project) { continue }
        foreach ($action in @((Get-ContractValue $project 'actions'))) { if ($null -ne $action) { $allActions.Add($action) } }
    }
    foreach ($index in 0..([Math]::Max(0, $allActions.Count - 1))) {
        if ($allActions.Count -eq 0) { break }
        $action = $allActions[$index]
        Test-ContractFields $action $actionFields $actionFields "actions[$index]" $errors
        $recovery = Get-ContractValue $action 'recovery'
        Test-ContractFields $recovery $recoveryFields $recoveryFields "actions[$index].recovery" $errors
    }

    $projectNames = @($projects | ForEach-Object { if ($null -ne $_) { Get-ContractValue $_ 'name' } })
    if ($projects.Count -ne 5) { $errors.Add('manifest must contain exactly five projects.') }
    if ((@($projectNames | Sort-Object -Unique).Count) -ne $projectNames.Count) { $errors.Add('project names must be unique.') }
    $destinations = @($projects | ForEach-Object { if ($null -ne $_) { [string](Get-ContractValue $_ 'destination_segment') } } | ForEach-Object { $_.ToLowerInvariant() })
    if ((@($destinations | Sort-Object -Unique).Count) -ne $destinations.Count) { $errors.Add('project destinations must be unique ignoring case.') }
    $toolIds = @($tools | ForEach-Object { if ($null -ne $_) { Get-ContractValue $_ 'id' } })
    if ((@($toolIds | Sort-Object -Unique).Count) -ne $toolIds.Count) { $errors.Add('tool IDs must be unique.') }
    $profileIds = @($profiles | ForEach-Object { if ($null -ne $_) { Get-ContractValue $_ 'id' } })
    if ((@($profileIds | Sort-Object -Unique).Count) -ne $profileIds.Count) { $errors.Add('environment profile IDs must be unique.') }
    $actionIds = @($allActions | ForEach-Object { Get-ContractValue $_ 'id' })
    if ((@($actionIds | Sort-Object -Unique).Count) -ne $actionIds.Count) { $errors.Add('action IDs must be globally unique.') }

    $expectedProjects = @(
        [pscustomobject]@{ name = 'dotfiles'; destination = 'dotfiles'; identity = 'github.com/ui-HookeyChiang/dotfiles'; clone = 'https://github.com/ui-HookeyChiang/dotfiles.git' },
        [pscustomobject]@{ name = 'skill-dev'; destination = 'skill-dev'; identity = 'github.com/ui-HookeyChiang/skill-dev'; clone = 'https://github.com/ui-HookeyChiang/skill-dev.git' },
        [pscustomobject]@{ name = 'Awesome-CV'; destination = 'Awesome-CV'; identity = 'github.com/ui-HookeyChiang/Awesome-CV'; clone = 'https://github.com/ui-HookeyChiang/Awesome-CV.git' },
        [pscustomobject]@{ name = 'telegram-claude-bridge'; destination = 'telegram-claude-bridge'; identity = 'github.com/ui-HookeyChiang/telegram-claude-bridge'; clone = 'https://github.com/ui-HookeyChiang/telegram-claude-bridge.git' },
        [pscustomobject]@{ name = 'stock-target-finder'; destination = 'stock-target-finder'; identity = 'github.com/ui-HookeyChiang/stock-target-finder'; clone = 'https://github.com/ui-HookeyChiang/stock-target-finder.git' }
    )
    foreach ($index in 0..($expectedProjects.Count - 1)) {
        if ($index -ge $projects.Count -or $null -eq $projects[$index]) { continue }
        $expected = $expectedProjects[$index]
        if ((Get-ContractValue $projects[$index] 'name') -cne $expected.name -or
            (Get-ContractValue $projects[$index] 'destination_segment') -cne $expected.destination -or
            (Get-ContractValue $projects[$index] 'canonical_identity') -cne $expected.identity -or
            (Get-ContractValue $projects[$index] 'clone_url') -cne $expected.clone) {
            $errors.Add("projects[$index] does not match the canonical project inventory.")
        }
    }

    $expectedProfileIds = @('tool-probe-v1', 'git-inspect-v1', 'git-clone-anonymous-future', 'git-clone-gcm-future')
    if (Compare-Object @($profileIds | Sort-Object -Unique) @($expectedProfileIds | Sort-Object)) { $errors.Add('manifest has an incomplete environment profile inventory.') }
    $expectedActionIds = @('checkout-root.create.deferred', 'shell-tests.deferred', 'services.deferred', 'repo.dotfiles.clone.deferred', 'dotfiles.host-integration.deferred', 'repo.skill-dev.clone.deferred', 'skill-dev.dependencies.deferred', 'repo.awesome-cv.clone.deferred', 'awesome-cv.dependencies.deferred', 'repo.telegram-bridge.clone.deferred', 'telegram-bridge.dependencies.deferred', 'repo.stock-finder.clone.deferred', 'stock-finder.dependencies.deferred')
    if (Compare-Object @($actionIds | Sort-Object -Unique) @($expectedActionIds | Sort-Object)) { $errors.Add('manifest has an incomplete action inventory.') }

    foreach ($profile in $profiles) {
        if ($null -eq $profile) { continue }
        $id = Get-ContractValue $profile 'id'
        $fixedValues = Get-ContractValue $profile 'fixed_values'
        if ([string]::IsNullOrWhiteSpace([string]$id) -or (Get-ContractValue $profile 'schema_version') -ne 1) { $errors.Add("environment profile '$id' has invalid identity or schema version.") }
        if ((Get-ContractValue $profile 'allowed_inputs') -isnot [array] -or (Get-ContractValue $profile 'denied_name_patterns') -isnot [array] -or $fixedValues -isnot [System.Collections.IDictionary]) { $errors.Add("environment profile '$id' has invalid collection types.") }
        if ((Get-ContractValue $profile 'credential_policy') -notin @('deny', 'required') -or (Get-ContractValue $profile 'network_policy') -notin @('deny', 'required')) { $errors.Add("environment profile '$id' has invalid policy.") }
        $allowInherited = Get-ContractValue $profile 'allow_inherited'
        if ($allowInherited -isnot [bool] -or $allowInherited) { $errors.Add("environment profile '$id' must deny inherited environment.") }
    }

    $expectedTools = [ordered]@{ pwsh = 'pwsh.exe'; scoop = 'scoop.cmd'; git = 'git.exe'; gh = 'gh.exe'; node = 'node.exe'; npm = 'npm.cmd'; python = 'python.exe'; uv = 'uv.exe'; jq = 'jq.exe'; yq = 'yq.exe'; fzf = 'fzf.exe'; fd = 'fd.exe'; 'ast-grep' = 'ast-grep.exe'; pdfinfo = 'pdfinfo.exe'; xelatex = 'xelatex.exe' }
    if ($tools.Count -ne $expectedTools.Count) { $errors.Add('manifest has an incomplete tool inventory.') }
    foreach ($expectedId in $expectedTools.Keys) {
        $matches = @($tools | Where-Object { $null -ne $_ -and (Get-ContractValue $_ 'id') -ceq $expectedId })
        if ($matches.Count -ne 1 -or (Get-ContractValue $matches[0] 'executable') -cne $expectedTools[$expectedId]) { $errors.Add("tool '$expectedId' has an invalid executable descriptor.") }
    }
    foreach ($tool in $tools) {
        if ($null -eq $tool) { continue }
        $id = Get-ContractValue $tool 'id'
        $executable = Get-ContractValue $tool 'executable'
        $environmentProfile = Get-ContractValue $tool 'environment_profile'
        $timeout = Get-ContractValue $tool 'timeout_seconds'
        $wrapper = Get-ContractValue $tool 'wrapper_policy'
        if ($environmentProfile -notin $profileIds) { $errors.Add("tool '$id' references an unknown environment profile.") }
        if ((Get-ContractValue $tool 'network_policy') -ne 'deny' -or $timeout -isnot [int] -or $timeout -le 0) { $errors.Add("tool '$id' has an unsafe probe policy.") }
        if ($executable -match '(?i)^(wsl|bash)(\.exe)?$') { $errors.Add("tool '$id' uses an unsafe executor.") }
        foreach ($projectReference in @((Get-ContractValue $tool 'required_projects'))) { if ($projectReference -notin $projectNames) { $errors.Add("tool '$id' references unknown project '$projectReference'.") } }
        if ($executable -like '*.cmd') {
            if ($null -eq $wrapper) { $errors.Add("tool '$id' lacks its reviewed command-wrapper policy.") }
            else {
                if ((Get-ContractValue $wrapper 'host_executable') -cne 'cmd.exe') { $errors.Add("tool '$id' lacks its reviewed command-wrapper policy.") }
                foreach ($flag in @('require_absolute_path', 'require_non_reparse', 'require_sha256', 'reviewed_content_required', 'fixed_arguments_only')) { if ((Get-ContractValue $wrapper $flag) -isnot [bool] -or -not (Get-ContractValue $wrapper $flag)) { $errors.Add("tool '$id' has unsafe wrapper field '$flag'.") } }
            }
        } elseif ($null -ne $wrapper) { $errors.Add("tool '$id' has an unexpected wrapper policy.") }
    }

    foreach ($project in $projects) {
        if ($null -eq $project) { continue }
        $name = Get-ContractValue $project 'name'
        foreach ($toolReference in @((Get-ContractValue $project 'required_tools'))) { if ($toolReference -notin $toolIds) { $errors.Add("project '$name' references unknown tool '$toolReference'.") } }
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
        if ($state -notin @('deferred', 'inspect') -or $credentialPolicy -notin @('deny', 'required', 'optional') -or $networkPolicy -notin @('deny', 'required', 'optional')) { $errors.Add("action '$id' has an invalid policy enum.") }
        if ($required -isnot [bool] -or (Get-ContractValue $action 'argv_template') -isnot [array] -or (Get-ContractValue $action 'prerequisites') -isnot [array]) { $errors.Add("action '$id' has invalid field types.") }
        foreach ($prerequisite in @((Get-ContractValue $action 'prerequisites'))) {
            $validReference = $prerequisite -in $actionIds -or ($prerequisite -match '^tool\.(.+)$' -and $Matches[1] -in $toolIds)
            if (-not $validReference) { $errors.Add("action '$id' references unknown prerequisite '$prerequisite'.") }
        }
        $recoveryKind = if ($null -eq $recovery) { $null } else { Get-ContractValue $recovery 'kind' }
        if ($required -and $recoveryKind -eq 'deferred' -and $state -ne 'deferred') { $errors.Add("action '$id' cannot execute with deferred recovery.") }
        $owner = if ($null -eq $recovery) { $null } else { Get-ContractValue $recovery 'owner' }
        $instructions = if ($null -eq $recovery) { $null } else { Get-ContractValue $recovery 'instructions' }
        $verification = if ($null -eq $recovery) { $null } else { Get-ContractValue $recovery 'verification' }
        if ([string]::IsNullOrWhiteSpace([string]$owner) -or [string]::IsNullOrWhiteSpace([string]$instructions) -or [string]::IsNullOrWhiteSpace([string]$verification)) { $errors.Add("action '$id' has incomplete recovery.") }
    }

    if ($null -ne $future) {
        foreach ($falseField in @('available_in_v1', 'approve_all', 'force', 'inherited_environment', 'credential_authorization')) {
            $value = Get-ContractValue $future $falseField
            if ($value -isnot [bool] -or $value) { $errors.Add("future_activation.$falseField must be false.") }
        }
        $revalidate = Get-ContractValue $future 'revalidate_immediately_before_spawn'
        if ($revalidate -isnot [bool] -or -not $revalidate -or (Get-ContractValue $future 'approval_scope') -ne 'one-action-one-invocation') { $errors.Add('future activation authority is not invocation-bound and revalidated.') }
        $descriptorFields = Get-ContractValue $future 'required_descriptor_fields'
        $expectedDescriptorFields = @('repository_path', 'normalized_remote', 'head_object_id', 'head_tree_id', 'input_file_sha256', 'executor_path', 'executor_sha256', 'working_directory', 'argv_sha256', 'environment_profile_id', 'environment_profile_sha256', 'manifest_schema_version', 'action_schema_version')
        if ($descriptorFields -isnot [array] -or (Compare-Object @($descriptorFields | Sort-Object -Unique) @($expectedDescriptorFields | Sort-Object))) { $errors.Add('future activation descriptor fields are incomplete.') }
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
    $requiredResults = @($Results | Where-Object { (Get-ContractValue $_ 'required') -eq $true })
    foreach ($result in $requiredResults) {
        $status = [string](Get-ContractValue $result 'status')
        if ($status -eq 'skipped') { $status = 'action_required' }
        if ($rank[$status] -gt $rank[$winner]) { $winner = $status }
    }
    return $winner
}

function Get-NativeBootstrapExitCode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Overall,
        [AllowNull()] [object] $Manifest,
        [object[]] $Results = @(),
        [object[]] $Plans = @(),
        [switch] $InvocationError,
        [switch] $InvariantFailure
    )
    if ($InvariantFailure) { return 30 }
    if ($InvocationError) { return 2 }
    if ($Overall -eq 'failed') { return 20 }
    $requiredDeferred = $false
    if ($null -ne $Manifest) {
        $manifestActions = [System.Collections.Generic.List[object]]::new()
        foreach ($action in @((Get-ContractValue $Manifest 'actions'))) { if ($null -ne $action) { $manifestActions.Add($action) } }
        foreach ($project in @((Get-ContractValue $Manifest 'projects'))) {
            if ($null -eq $project) { continue }
            foreach ($action in @((Get-ContractValue $project 'actions'))) { if ($null -ne $action) { $manifestActions.Add($action) } }
        }
        $requiredDeferred = @($manifestActions | Where-Object { (Get-ContractValue $_ 'required') -eq $true -and (Get-ContractValue $_ 'v1_state') -eq 'deferred' }).Count -gt 0
    }
    $requiredResult = @($Results | Where-Object { (Get-ContractValue $_ 'required') -eq $true -and (Get-ContractValue $_ 'status') -in @('action_required', 'skipped') }).Count -gt 0
    $requiredPlan = @($Plans | Where-Object {
        (Get-ContractValue $_ 'required') -eq $true -and (
            (Get-ContractValue $_ 'state') -eq 'blocked' -or
            (Get-ContractValue (Get-ContractValue $_ 'recovery') 'kind') -eq 'deferred'
        )
    }).Count -gt 0
    if ($requiredDeferred -or $requiredResult -or $requiredPlan -or $Overall -eq 'action_required') { return 10 }
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
    $credentialName = '[A-Z0-9_]*(?:TOKEN|SECRET|PASSWORD|CREDENTIAL|API_KEY)[A-Z0-9_]*'
    $result = [regex]::Replace($result, "(?i)\b($credentialName)\s*=\s*(?:`"(?:\\.|[^`"\\])*`"|'(?:''|[^'])*'|(?![`"'])\S+)", '$1=<redacted>')
    $result = [regex]::Replace($result, "(?im)\b($credentialName)\s*=\s*(?!<redacted>)[^\r\n]*", '$1=<redacted>')
    $result = $result -replace '(?i)(https?://)[^/@\s]+@', '$1<redacted>@'
    foreach ($root in $ProfileRoots) { if (-not [string]::IsNullOrWhiteSpace($root)) { $result = $result.Replace($root, '<profile-root>', [StringComparison]::OrdinalIgnoreCase) } }
    return [regex]::Replace($result, '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]', { param($match) "\u$([int][char]$match.Value).ToString('x4')" })
}

function ConvertTo-CanonicalContractValue {
    param([AllowNull()] [object] $Value, [string] $PropertyName = '')
    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Collections.IDictionary] -or $Value.GetType().FullName -eq 'System.Management.Automation.PSCustomObject') {
        $ordered = [ordered]@{}
        foreach ($key in @(Get-ContractKeys $Value | Sort-Object)) { $ordered[$key] = ConvertTo-CanonicalContractValue (Get-ContractValue $Value $key) $key }
        return $ordered
    }
    if ($Value -is [array]) {
        $items = @($Value | ForEach-Object { ConvertTo-CanonicalContractValue $_ $PropertyName })
        if ($PropertyName -in @('affected', 'authorizations', 'blocked_by', 'prerequisites', 'targets')) { $items = @($items | Sort-Object { $_ | ConvertTo-Json -Depth 30 -Compress }) }
        elseif ($PropertyName -eq 'plans') { $items = @($items | Sort-Object @{ Expression = { Get-ContractValue $_ 'action_id' } }, @{ Expression = { Get-ContractValue $_ 'target' } }) }
        elseif ($PropertyName -eq 'results') { $items = @($items | Sort-Object @{ Expression = { Get-ContractValue $_ 'scope' } }, @{ Expression = { Get-ContractValue $_ 'name' } }, @{ Expression = { Get-ContractValue $_ 'code' } }) }
        elseif ($PropertyName -eq 'mutations') { $items = @($items | Sort-Object @{ Expression = { Get-ContractValue $_ 'action_id' } }) }
        elseif ($PropertyName -eq 'diagnostics') { $items = @($items | Sort-Object @{ Expression = { Get-ContractValue $_ 'code' } }, @{ Expression = { Get-ContractValue $_ 'message' } }) }
        elseif ($PropertyName -eq 'errors') { $items = @($items | Sort-Object @{ Expression = { Get-ContractValue $_ 'code' } }, @{ Expression = { Get-ContractValue $_ 'stage' } }, @{ Expression = { Get-ContractValue $_ 'message' } }) }
        return ,$items
    }
    return $Value
}

function ConvertTo-NativeBootstrapReportJson {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [object] $Report)
    $order = @('schema_version', 'report_kind', 'command', 'execution_provenance', 'check_contract_ready', 'projects_dir', 'offline', 'overall', 'exit_code', 'authorizations', 'plans', 'results', 'mutations', 'diagnostics', 'errors', 'fallback')
    $output = [ordered]@{}
    foreach ($name in $order) {
        if ($name -notin @(Get-ContractKeys $Report)) { continue }
        if ($Report -is [System.Collections.IDictionary]) { $value = $Report[$name] }
        else { $value = $Report.PSObject.Properties[$name].Value }
        $output[$name] = ConvertTo-CanonicalContractValue $value $name
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
