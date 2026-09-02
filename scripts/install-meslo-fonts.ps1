#Requires -Version 5.1
<#
.SYNOPSIS
  Install MesloLGS NF for tmux powerline + p10k on native Windows.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$FontBase = 'https://github.com/romkatv/powerlevel10k-media/raw/master'
$Variants = @('Regular', 'Bold', 'Italic', 'Bold Italic')
$FontFace = 'MesloLGS NF'
$FontSize = 14
$FontsDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'

function Write-Step($Message) { Write-Host "    $Message" }

function Install-MesloFonts {
    New-Item -ItemType Directory -Force -Path $FontsDir | Out-Null
    $installed = $false
    foreach ($variant in $Variants) {
        $fileName = "MesloLGS NF $variant.ttf"
        $dest = Join-Path $FontsDir $fileName
        if (Test-Path -LiteralPath $dest) {
            Write-Step "skip Meslo font (present: $dest)"
            continue
        }
        $url = "$FontBase/MesloLGS%20NF%20$($variant -replace ' ', '%20').ttf"
        Write-Step "downloading $fileName"
        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
        $installed = $true
    }
    if ($installed) {
        Write-Step 'MesloLGS NF installed for Windows Terminal / conhost'
    }
}

function Get-WindowsTerminalSettingsPaths {
    $local = $env:LOCALAPPDATA
    @(
        (Join-Path $local 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json')
        (Join-Path $local 'Microsoft\Windows Terminal\settings.json')
    )
}

function Update-WindowsTerminalFont {
    $updated = $false
    foreach ($path in Get-WindowsTerminalSettingsPaths) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $json = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $json.profiles) { $json | Add-Member -NotePropertyName profiles -NotePropertyValue ([pscustomobject]@{}) }
        if (-not $json.profiles.defaults) { $json.profiles | Add-Member -NotePropertyName defaults -NotePropertyValue ([pscustomobject]@{}) }
        if (-not $json.profiles.defaults.font) { $json.profiles.defaults | Add-Member -NotePropertyName font -NotePropertyValue ([pscustomobject]@{}) }
        $current = [string]$json.profiles.defaults.font.face
        if ($current -like '*Meslo*') {
            Write-Step "skip Windows Terminal font (already Meslo: $path)"
            continue
        }
        $json.profiles.defaults.font | Add-Member -NotePropertyName face -NotePropertyValue $FontFace -Force
        $json.profiles.defaults.font | Add-Member -NotePropertyName size -NotePropertyValue $FontSize -Force
        $json | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding UTF8
        Write-Step "updated Windows Terminal font in $path"
        $updated = $true
    }
    if (-not $updated) {
        Write-Step 'skip Windows Terminal font (already Meslo or settings.json not found)'
    }
    return $updated
}

function Write-TmuxSop {
    Write-Step 'SOP: open a new Windows Terminal tab (existing tabs keep the old font)'
    Write-Step 'SOP (WSL tmux): tmux set-environment -g TMUX_CONF_LOCAL "$HOME/dotfiles/.tmux.conf.local"'
    Write-Step 'SOP (WSL tmux): tmux source-file ~/.config/tmux/.tmux.conf'
    Write-Step 'SOP: docs/specs/done/2026-09-02-tmux-powerline-font-sop.md'
}

Write-Host '==> install-meslo-fonts.ps1'
Install-MesloFonts
if (Update-WindowsTerminalFont) { Write-TmuxSop }
Write-Host '==> done'
