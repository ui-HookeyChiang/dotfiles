[CmdletBinding()]
param(
    [string]$ProjectsDir = 'D:\projects',
    [switch]$SkipTools,
    [switch]$SkipProjects,
    [switch]$SkipSkills,
    [switch]$SkipRtk,
    [switch]$ApplyClaudePermissions
)

$ErrorActionPreference = 'Stop'
$repos = @(
    @{ Name = 'dotfiles'; Url = 'git@github.com:ui-HookeyChiang/dotfiles.git' },
    @{ Name = 'skill-dev'; Url = 'git@github.com:ui-HookeyChiang/skill-dev.git' },
    @{ Name = 'Awesome-CV'; Url = 'git@github.com:ui-HookeyChiang/Awesome-CV.git' },
    @{ Name = 'telegram-claude-bridge'; Url = 'git@github.com:ui-HookeyChiang/telegram-claude-bridge.git' },
    @{ Name = 'stock-target-finder'; Url = 'git@github.com:ui-HookeyChiang/stock-target-finder.git' }
)

function Require-Command([string]$Name, [string]$Hint) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) { throw "Missing $Name. $Hint" }
}

function Add-UserPath([string]$Entry) {
    $current = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (($current -split ';') -notcontains $Entry) {
        [Environment]::SetEnvironmentVariable('Path', (($current.TrimEnd(';') + ';' + $Entry).TrimStart(';')), 'User')
    }
    if (($env:Path -split ';') -notcontains $Entry) { $env:Path = "$Entry;$env:Path" }
}

function Install-RtkWindows {
    $version = 'v0.45.0'
    $asset = 'rtk-x86_64-pc-windows-msvc.zip'
    $binDir = Join-Path $HOME '.local\bin'
    $target = Join-Path $binDir 'rtk.exe'
    if (Test-Path -LiteralPath $target) { return }
    New-Item -ItemType Directory -Force -Path $binDir | Out-Null
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("rtk-{0}.zip" -f ([guid]::NewGuid()))
    $url = "https://github.com/rtk-ai/rtk/releases/download/$version/$asset"
    try {
        Invoke-WebRequest -Uri $url -OutFile $tmp
        $extract = Join-Path ([IO.Path]::GetTempPath()) ("rtk-{0}" -f ([guid]::NewGuid()))
        Expand-Archive -LiteralPath $tmp -DestinationPath $extract -Force
        $exe = Get-ChildItem -LiteralPath $extract -Filter 'rtk.exe' -Recurse | Select-Object -First 1
        if (-not $exe) { throw "rtk.exe was not present in $asset" }
        Copy-Item -LiteralPath $exe.FullName -Destination $target -Force
        Add-UserPath $binDir
    } finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        if ($extract) { Remove-Item -LiteralPath $extract -Recurse -Force -ErrorAction SilentlyContinue }
    }
    Require-Command rtk 'The official Windows release was not installed.'
    & rtk --version
    & rtk init -g
}

if (-not $SkipTools) {
    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
        Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
    }
    scoop install git gh nodejs-lts python uv jq yq fzf fd ast-grep poppler miktex
}

if (-not $SkipRtk) { Install-RtkWindows }

Require-Command git 'Run bootstrap without -SkipTools.'
Require-Command gh 'Run bootstrap without -SkipTools.'
if (-not (gh auth status 2>$null)) {
    gh auth login --hostname github.com --git-protocol ssh --web
}
gh auth setup-git

New-Item -ItemType Directory -Force -Path $ProjectsDir | Out-Null
foreach ($repo in $repos) {
    $destination = Join-Path $ProjectsDir $repo.Name
    if (-not (Test-Path (Join-Path $destination '.git'))) {
        git clone --recurse-submodules $repo.Url $destination
    }
    git config --global --add safe.directory ($destination -replace '\\', '/')
}

$scoopRoot = if ($env:SCOOP) { $env:SCOOP } else { Join-Path $HOME 'scoop' }
$gitBash = @(
    (Join-Path $scoopRoot 'apps\git\current\bin\bash.exe'),
    'C:\Program Files\Git\bin\bash.exe'
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $gitBash) { throw 'Git Bash was not found.' }

$agentBin = Join-Path $HOME '.local\bin'
New-Item -ItemType Directory -Force -Path $agentBin | Out-Null
Copy-Item "$PSScriptRoot\agent-cli.cmd" "$agentBin\agent-cli.cmd" -Force
Copy-Item "$PSScriptRoot\agent-cli.ps1" "$agentBin\agent-cli.ps1" -Force
Add-UserPath $agentBin
$profile = $PROFILE.CurrentUserCurrentHost
New-Item -ItemType Directory -Force -Path (Split-Path $profile) | Out-Null
$profileText = if (Test-Path $profile) { Get-Content -Raw $profile } else { '' }
$profileText = [regex]::Replace($profileText, '(?s)\n?# >>> dotfiles agent-cli >>>.*?# <<< dotfiles agent-cli <<<', '')
$profileText += "`n# >>> dotfiles agent-cli >>>`nfunction agent-cli { & '$agentBin\agent-cli.ps1' @args }`n# <<< dotfiles agent-cli <<<`n"
Set-Content -LiteralPath $profile -Value $profileText -NoNewline

if (-not $SkipSkills) {
    & $gitBash -lc "cd '$($ProjectsDir -replace '\\', '/')/skill-dev' && ./install.sh --skip-bins --register-hooks"
    if ($ApplyClaudePermissions) {
        Copy-Item "$ProjectsDir\skill-dev\.claude\settings.json" "$HOME\.claude\settings.json" -Force
    }
}

if (-not $SkipProjects) {
    & npm --prefix "$ProjectsDir\Awesome-CV\src\present" install --no-audit --no-fund
    & npm --prefix "$ProjectsDir\telegram-claude-bridge" ci --no-audit --no-fund
    if (-not (Test-Path "$ProjectsDir\stock-target-finder\.env")) {
        Copy-Item "$ProjectsDir\stock-target-finder\.env.example" "$ProjectsDir\stock-target-finder\.env"
    }
    Push-Location "$ProjectsDir\stock-target-finder"
    try { uv sync } finally { Pop-Location }
}

Write-Host 'Bootstrap complete. Fill in .env secrets before enabling Telegram or stock services.'
