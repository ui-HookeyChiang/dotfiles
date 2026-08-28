@{
    schema_version = 1
    environment_profiles = @(
        @{
            id = 'tool-probe-v1'; schema_version = 1
            allowed_inputs = @('ComSpec', 'SystemRoot', 'TEMP', 'TMP')
            fixed_values = @{ DOTNET_CLI_UI_LANGUAGE = 'en-US'; NO_COLOR = '1'; PYTHONUTF8 = '1' }
            denied_name_patterns = @('*CREDENTIAL*', '*KEY*', '*SECRET*', '*TOKEN*', 'APPDATA', 'HOME', 'LOCALAPPDATA', 'USERPROFILE')
            credential_policy = 'deny'; network_policy = 'deny'; allow_inherited = $false
        }
        @{
            id = 'git-inspect-v1'; schema_version = 1
            allowed_inputs = @('ComSpec', 'SystemRoot', 'TEMP', 'TMP')
            fixed_values = @{ GCM_INTERACTIVE = 'Never'; GIT_CONFIG_GLOBAL = 'NUL'; GIT_CONFIG_NOSYSTEM = '1'; GIT_OPTIONAL_LOCKS = '0'; GIT_TERMINAL_PROMPT = '0' }
            denied_name_patterns = @('*CREDENTIAL*', '*KEY*', '*SECRET*', '*TOKEN*', 'APPDATA', 'GIT_ASKPASS', 'GIT_SSH', 'GIT_SSH_COMMAND', 'HOME', 'LOCALAPPDATA', 'SSH_ASKPASS', 'USERPROFILE')
            credential_policy = 'deny'; network_policy = 'deny'; allow_inherited = $false
        }
        @{
            id = 'git-clone-anonymous-future'; schema_version = 1
            allowed_inputs = @('ComSpec', 'SystemRoot', 'TEMP', 'TMP')
            fixed_values = @{ GCM_INTERACTIVE = 'Never'; GIT_CONFIG_NOSYSTEM = '1'; GIT_TERMINAL_PROMPT = '0' }
            denied_name_patterns = @('*CREDENTIAL*', '*KEY*', '*SECRET*', '*TOKEN*', 'APPDATA', 'GIT_ASKPASS', 'HOME', 'LOCALAPPDATA', 'SSH_ASKPASS', 'USERPROFILE')
            credential_policy = 'deny'; network_policy = 'required'; allow_inherited = $false
        }
        @{
            id = 'git-clone-gcm-future'; schema_version = 1
            allowed_inputs = @('ComSpec', 'SystemRoot', 'TEMP', 'TMP')
            fixed_values = @{ GCM_INTERACTIVE = 'Never'; GIT_CONFIG_NOSYSTEM = '1'; GIT_TERMINAL_PROMPT = '0' }
            denied_name_patterns = @('*KEY*', '*SECRET*', '*TOKEN*', 'GIT_ASKPASS', 'SSH_ASKPASS')
            credential_policy = 'required'; network_policy = 'required'; allow_inherited = $false
        }
    )
    tools = @(
        @{ id = 'pwsh'; executable = 'pwsh.exe'; resolver_roots = @('ProgramFiles', 'ScoopApps'); version_argv = @('-NoProfile', '-Command', '$PSVersionTable.PSVersion.ToString()'); version_parser = 'system-version'; version_constraint = '>=7.4'; required_projects = @('dotfiles', 'skill-dev', 'Awesome-CV', 'telegram-claude-bridge', 'stock-target-finder'); environment_profile = 'tool-probe-v1'; timeout_seconds = 10; network_policy = 'deny'; remediation = 'Install PowerShell 7.4+ separately, then reopen the terminal.'; wrapper_policy = $null }
        @{ id = 'scoop'; executable = 'scoop.cmd'; resolver_roots = @('ScoopShims'); version_argv = @('--version'); version_parser = 'first-version'; version_constraint = 'supported-current'; required_projects = @('dotfiles', 'skill-dev', 'Awesome-CV', 'telegram-claude-bridge', 'stock-target-finder'); environment_profile = 'tool-probe-v1'; timeout_seconds = 10; network_policy = 'deny'; remediation = 'Install Scoop from reviewed official instructions; do not pipe remote text into this bootstrap.'; wrapper_policy = @{ host_executable = 'cmd.exe'; require_absolute_path = $true; require_non_reparse = $true; require_sha256 = $true; reviewed_content_required = $true; fixed_arguments_only = $true } }
        @{ id = 'git'; executable = 'git.exe'; resolver_roots = @('ScoopApps', 'ProgramFiles'); version_argv = @('--version'); version_parser = 'git-version'; version_constraint = '>=2.45'; required_projects = @('dotfiles', 'skill-dev', 'Awesome-CV', 'telegram-claude-bridge', 'stock-target-finder'); environment_profile = 'tool-probe-v1'; timeout_seconds = 10; network_policy = 'deny'; remediation = 'scoop install git'; wrapper_policy = $null }
        @{ id = 'gh'; executable = 'gh.exe'; resolver_roots = @('ScoopApps', 'ProgramFiles'); version_argv = @('--version'); version_parser = 'first-version'; version_constraint = '>=2.50'; required_projects = @(); environment_profile = 'tool-probe-v1'; timeout_seconds = 10; network_policy = 'deny'; remediation = 'scoop install gh; run gh auth login separately.'; wrapper_policy = $null }
        @{ id = 'node'; executable = 'node.exe'; resolver_roots = @('ScoopApps', 'ProgramFiles'); version_argv = @('--version'); version_parser = 'node-version'; version_constraint = '>=20'; required_projects = @('Awesome-CV', 'telegram-claude-bridge'); environment_profile = 'tool-probe-v1'; timeout_seconds = 10; network_policy = 'deny'; remediation = 'scoop install nodejs-lts'; wrapper_policy = $null }
        @{ id = 'npm'; executable = 'npm.cmd'; resolver_roots = @('ScoopApps'); version_argv = @('--version'); version_parser = 'system-version'; version_constraint = '>=10'; required_projects = @('Awesome-CV', 'telegram-claude-bridge'); environment_profile = 'tool-probe-v1'; timeout_seconds = 10; network_policy = 'deny'; remediation = 'scoop install nodejs-lts'; wrapper_policy = @{ host_executable = 'cmd.exe'; require_absolute_path = $true; require_non_reparse = $true; require_sha256 = $true; reviewed_content_required = $true; fixed_arguments_only = $true } }
        @{ id = 'python'; executable = 'python.exe'; resolver_roots = @('ScoopApps', 'ProgramFiles'); version_argv = @('--version'); version_parser = 'python-version'; version_constraint = '>=3.12'; required_projects = @('stock-target-finder'); environment_profile = 'tool-probe-v1'; timeout_seconds = 10; network_policy = 'deny'; remediation = 'scoop install python uv'; wrapper_policy = $null }
        @{ id = 'uv'; executable = 'uv.exe'; resolver_roots = @('ScoopApps'); version_argv = @('--version'); version_parser = 'first-version'; version_constraint = '>=0.8'; required_projects = @('stock-target-finder'); environment_profile = 'tool-probe-v1'; timeout_seconds = 10; network_policy = 'deny'; remediation = 'scoop install python uv'; wrapper_policy = $null }
        @{ id = 'jq'; executable = 'jq.exe'; resolver_roots = @('ScoopApps'); version_argv = @('--version'); version_parser = 'first-version'; version_constraint = '>=1.7'; required_projects = @('dotfiles', 'skill-dev'); environment_profile = 'tool-probe-v1'; timeout_seconds = 10; network_policy = 'deny'; remediation = 'scoop install jq yq'; wrapper_policy = $null }
        @{ id = 'yq'; executable = 'yq.exe'; resolver_roots = @('ScoopApps'); version_argv = @('--version'); version_parser = 'first-version'; version_constraint = '>=4.44'; required_projects = @('dotfiles', 'skill-dev'); environment_profile = 'tool-probe-v1'; timeout_seconds = 10; network_policy = 'deny'; remediation = 'scoop install jq yq'; wrapper_policy = $null }
        @{ id = 'fzf'; executable = 'fzf.exe'; resolver_roots = @('ScoopApps'); version_argv = @('--version'); version_parser = 'first-version'; version_constraint = '>=0.53'; required_projects = @('dotfiles'); environment_profile = 'tool-probe-v1'; timeout_seconds = 10; network_policy = 'deny'; remediation = 'scoop install fzf fd'; wrapper_policy = $null }
        @{ id = 'fd'; executable = 'fd.exe'; resolver_roots = @('ScoopApps'); version_argv = @('--version'); version_parser = 'first-version'; version_constraint = '>=10'; required_projects = @('dotfiles'); environment_profile = 'tool-probe-v1'; timeout_seconds = 10; network_policy = 'deny'; remediation = 'scoop install fzf fd'; wrapper_policy = $null }
        @{ id = 'ast-grep'; executable = 'ast-grep.exe'; resolver_roots = @('ScoopApps'); version_argv = @('--version'); version_parser = 'first-version'; version_constraint = '>=0.27'; required_projects = @('skill-dev'); environment_profile = 'tool-probe-v1'; timeout_seconds = 10; network_policy = 'deny'; remediation = 'scoop install ast-grep'; wrapper_policy = $null }
        @{ id = 'pdfinfo'; executable = 'pdfinfo.exe'; resolver_roots = @('ScoopApps'); version_argv = @('-v'); version_parser = 'first-version'; version_constraint = '>=24'; required_projects = @('Awesome-CV'); environment_profile = 'tool-probe-v1'; timeout_seconds = 10; network_policy = 'deny'; remediation = 'scoop install poppler miktex; finish MiKTeX setup separately.'; wrapper_policy = $null }
        @{ id = 'xelatex'; executable = 'xelatex.exe'; resolver_roots = @('ScoopApps'); version_argv = @('--version'); version_parser = 'first-version'; version_constraint = '>=24'; required_projects = @('Awesome-CV'); environment_profile = 'tool-probe-v1'; timeout_seconds = 10; network_policy = 'deny'; remediation = 'scoop install poppler miktex; finish MiKTeX setup separately.'; wrapper_policy = $null }
    )
    actions = @(
        @{
            id = 'checkout-root.create.deferred'; phase = 'host'; kind = 'create-directory'; executor_id = 'none'; argv_template = @(); working_directory = '{projects_dir}'; checkout_effect = 'configure'; credential_policy = 'deny'; network_policy = 'deny'; dirty_policy = 'require-clean'; required = $true; v1_state = 'deferred'; prerequisites = @(); success_probe = 'checkout-root-exists'
            recovery = @{ kind = 'deferred'; owner = 'dotfiles native bootstrap'; affected = @('{projects_dir}'); instructions = 'Activation is deferred; version 1 creates no checkout root.'; verification = 'Confirm the checkout root remains absent or unchanged.' }
        }
        @{
            id = 'shell-tests.deferred'; phase = 'shell'; kind = 'execute'; executor_id = 'none'; argv_template = @(); working_directory = '{projects_dir}'; checkout_effect = 'execute'; credential_policy = 'deny'; network_policy = 'deny'; dirty_policy = 'require-clean'; required = $true; v1_state = 'deferred'; prerequisites = @(); success_probe = 'issue-08-contract-defined'
            recovery = @{ kind = 'deferred'; owner = 'issue 08'; affected = @(); instructions = 'Issue 08 must define the shell and test actions before activation.'; verification = 'Validate the successor issue 08 contract.' }
        }
        @{
            id = 'services.deferred'; phase = 'service'; kind = 'configure'; executor_id = 'none'; argv_template = @(); working_directory = '{projects_dir}'; checkout_effect = 'configure'; credential_policy = 'deny'; network_policy = 'deny'; dirty_policy = 'require-clean'; required = $true; v1_state = 'deferred'; prerequisites = @(); success_probe = 'issue-09-contract-defined'
            recovery = @{ kind = 'deferred'; owner = 'issue 09'; affected = @(); instructions = 'Issue 09 must define service readiness before activation.'; verification = 'Validate the successor issue 09 contract.' }
        }
    )
    projects = @(
        @{
            name = 'dotfiles'; destination_segment = 'dotfiles'; canonical_identity = 'github.com/ui-HookeyChiang/dotfiles'; clone_url = 'https://github.com/ui-HookeyChiang/dotfiles.git'; required_tools = @('pwsh', 'scoop', 'git', 'fzf', 'fd', 'jq', 'yq'); readiness_probes = @('repository-identity', 'repository-dirty-state')
            actions = @(
                @{ id = 'repo.dotfiles.clone.deferred'; phase = 'checkout'; kind = 'clone'; executor_id = 'git'; argv_template = @('clone', '--', '{clone_url}', '{destination}'); working_directory = '{projects_dir}'; checkout_effect = 'install'; credential_policy = 'optional'; network_policy = 'required'; dirty_policy = 'require-clean'; required = $true; v1_state = 'deferred'; prerequisites = @('tool.git'); success_probe = 'repository-identity'; recovery = @{ kind = 'deferred'; owner = 'dotfiles native bootstrap'; affected = @('{destination}'); instructions = 'Activation is deferred; version 1 performs no clone.'; verification = 'Confirm the destination remains absent or unchanged.' } }
                @{ id = 'dotfiles.host-integration.deferred'; phase = 'integration'; kind = 'configure'; executor_id = 'none'; argv_template = @(); working_directory = '{destination}'; checkout_effect = 'configure'; credential_policy = 'deny'; network_policy = 'deny'; dirty_policy = 'require-clean'; required = $true; v1_state = 'deferred'; prerequisites = @('repo.dotfiles.clone.deferred'); success_probe = 'host-integration-contract-defined'; recovery = @{ kind = 'deferred'; owner = 'dotfiles'; affected = @('Git global configuration', 'PowerShell profile', 'PATH'); instructions = 'Host integration is deferred and unavailable in version 1.'; verification = 'Confirm host configuration is unchanged.' } }
            )
        }
        @{
            name = 'skill-dev'; destination_segment = 'skill-dev'; canonical_identity = 'github.com/ui-HookeyChiang/skill-dev'; clone_url = 'https://github.com/ui-HookeyChiang/skill-dev.git'; required_tools = @('pwsh', 'scoop', 'git', 'ast-grep', 'jq', 'yq'); readiness_probes = @('repository-identity', 'repository-dirty-state')
            actions = @(
                @{ id = 'repo.skill-dev.clone.deferred'; phase = 'checkout'; kind = 'clone'; executor_id = 'git'; argv_template = @('clone', '--', '{clone_url}', '{destination}'); working_directory = '{projects_dir}'; checkout_effect = 'install'; credential_policy = 'optional'; network_policy = 'required'; dirty_policy = 'require-clean'; required = $true; v1_state = 'deferred'; prerequisites = @('tool.git'); success_probe = 'repository-identity'; recovery = @{ kind = 'deferred'; owner = 'dotfiles native bootstrap'; affected = @('{destination}'); instructions = 'Activation is deferred; version 1 performs no clone.'; verification = 'Confirm the destination remains absent or unchanged.' } }
                @{ id = 'skill-dev.dependencies.deferred'; phase = 'dependencies'; kind = 'install'; executor_id = 'none'; argv_template = @(); working_directory = '{destination}'; checkout_effect = 'install'; credential_policy = 'deny'; network_policy = 'optional'; dirty_policy = 'require-clean'; required = $true; v1_state = 'deferred'; prerequisites = @('repo.skill-dev.clone.deferred'); success_probe = 'dependencies-contract-defined'; recovery = @{ kind = 'deferred'; owner = 'skill-dev'; affected = @('{destination}'); instructions = 'Checkout dependency installation is deferred and unavailable in version 1.'; verification = 'Confirm the checkout and host are unchanged.' } }
            )
        }
        @{
            name = 'Awesome-CV'; destination_segment = 'Awesome-CV'; canonical_identity = 'github.com/ui-HookeyChiang/Awesome-CV'; clone_url = 'https://github.com/ui-HookeyChiang/Awesome-CV.git'; required_tools = @('pwsh', 'scoop', 'git', 'node', 'npm', 'pdfinfo', 'xelatex'); readiness_probes = @('repository-identity', 'repository-dirty-state')
            actions = @(
                @{ id = 'repo.awesome-cv.clone.deferred'; phase = 'checkout'; kind = 'clone'; executor_id = 'git'; argv_template = @('clone', '--', '{clone_url}', '{destination}'); working_directory = '{projects_dir}'; checkout_effect = 'install'; credential_policy = 'optional'; network_policy = 'required'; dirty_policy = 'require-clean'; required = $true; v1_state = 'deferred'; prerequisites = @('tool.git'); success_probe = 'repository-identity'; recovery = @{ kind = 'deferred'; owner = 'dotfiles native bootstrap'; affected = @('{destination}'); instructions = 'Activation is deferred; version 1 performs no clone.'; verification = 'Confirm the destination remains absent or unchanged.' } }
                @{ id = 'awesome-cv.dependencies.deferred'; phase = 'dependencies'; kind = 'install'; executor_id = 'npm'; argv_template = @('ci'); working_directory = '{destination}'; checkout_effect = 'install'; credential_policy = 'deny'; network_policy = 'required'; dirty_policy = 'require-clean'; required = $true; v1_state = 'deferred'; prerequisites = @('repo.awesome-cv.clone.deferred', 'tool.npm'); success_probe = 'dependencies-contract-defined'; recovery = @{ kind = 'deferred'; owner = 'Awesome-CV'; affected = @('{destination}'); instructions = 'Checkout dependency installation is deferred and unavailable in version 1.'; verification = 'Confirm the checkout and host are unchanged.' } }
            )
        }
        @{
            name = 'telegram-claude-bridge'; destination_segment = 'telegram-claude-bridge'; canonical_identity = 'github.com/ui-HookeyChiang/telegram-claude-bridge'; clone_url = 'https://github.com/ui-HookeyChiang/telegram-claude-bridge.git'; required_tools = @('pwsh', 'scoop', 'git', 'node', 'npm'); readiness_probes = @('repository-identity', 'repository-dirty-state')
            actions = @(
                @{ id = 'repo.telegram-bridge.clone.deferred'; phase = 'checkout'; kind = 'clone'; executor_id = 'git'; argv_template = @('clone', '--', '{clone_url}', '{destination}'); working_directory = '{projects_dir}'; checkout_effect = 'install'; credential_policy = 'optional'; network_policy = 'required'; dirty_policy = 'require-clean'; required = $true; v1_state = 'deferred'; prerequisites = @('tool.git'); success_probe = 'repository-identity'; recovery = @{ kind = 'deferred'; owner = 'dotfiles native bootstrap'; affected = @('{destination}'); instructions = 'Activation is deferred; version 1 performs no clone.'; verification = 'Confirm the destination remains absent or unchanged.' } }
                @{ id = 'telegram-bridge.dependencies.deferred'; phase = 'dependencies'; kind = 'install'; executor_id = 'npm'; argv_template = @('ci'); working_directory = '{destination}'; checkout_effect = 'install'; credential_policy = 'deny'; network_policy = 'required'; dirty_policy = 'require-clean'; required = $true; v1_state = 'deferred'; prerequisites = @('repo.telegram-bridge.clone.deferred', 'tool.npm'); success_probe = 'dependencies-contract-defined'; recovery = @{ kind = 'deferred'; owner = 'telegram-claude-bridge'; affected = @('{destination}'); instructions = 'Checkout dependency installation is deferred and unavailable in version 1.'; verification = 'Confirm the checkout and host are unchanged.' } }
            )
        }
        @{
            name = 'stock-target-finder'; destination_segment = 'stock-target-finder'; canonical_identity = 'github.com/ui-HookeyChiang/stock-target-finder'; clone_url = 'https://github.com/ui-HookeyChiang/stock-target-finder.git'; required_tools = @('pwsh', 'scoop', 'git', 'python', 'uv'); readiness_probes = @('repository-identity', 'repository-dirty-state')
            actions = @(
                @{ id = 'repo.stock-finder.clone.deferred'; phase = 'checkout'; kind = 'clone'; executor_id = 'git'; argv_template = @('clone', '--', '{clone_url}', '{destination}'); working_directory = '{projects_dir}'; checkout_effect = 'install'; credential_policy = 'optional'; network_policy = 'required'; dirty_policy = 'require-clean'; required = $true; v1_state = 'deferred'; prerequisites = @('tool.git'); success_probe = 'repository-identity'; recovery = @{ kind = 'deferred'; owner = 'dotfiles native bootstrap'; affected = @('{destination}'); instructions = 'Activation is deferred; version 1 performs no clone.'; verification = 'Confirm the destination remains absent or unchanged.' } }
                @{ id = 'stock-finder.dependencies.deferred'; phase = 'dependencies'; kind = 'install'; executor_id = 'uv'; argv_template = @('sync'); working_directory = '{destination}'; checkout_effect = 'install'; credential_policy = 'deny'; network_policy = 'required'; dirty_policy = 'require-clean'; required = $true; v1_state = 'deferred'; prerequisites = @('repo.stock-finder.clone.deferred', 'tool.uv'); success_probe = 'dependencies-contract-defined'; recovery = @{ kind = 'deferred'; owner = 'stock-target-finder'; affected = @('{destination}'); instructions = 'Checkout dependency installation is deferred and unavailable in version 1.'; verification = 'Confirm the checkout and host are unchanged.' } }
            )
        }
    )
    future_activation = @{
        available_in_v1 = $false; approval_scope = 'one-action-one-invocation'; approve_all = $false; force = $false; inherited_environment = $false; credential_authorization = $false
        required_descriptor_fields = @('repository_path', 'normalized_remote', 'head_object_id', 'head_tree_id', 'input_file_sha256', 'executor_path', 'executor_sha256', 'working_directory', 'argv_sha256', 'environment_profile_id', 'environment_profile_sha256', 'manifest_schema_version', 'action_schema_version')
        revalidate_immediately_before_spawn = $true
    }
}
