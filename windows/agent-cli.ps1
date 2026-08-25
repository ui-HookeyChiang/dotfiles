[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Arguments
)

# This is deliberately only a Windows-friendly launcher. The argument
# contract and backend normalization belong to cross-cli-dispatch's adapter.
$adapterCandidates = @(
    $env:CROSS_CLI_ADAPTER,
    (Join-Path $PSScriptRoot '..\..\skill-dev\cross-cli-dispatch\scripts\cli_adapter.py'),
    (Join-Path $HOME '.agents\skills\cross-cli-dispatch\scripts\cli_adapter.py')
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
if (-not $adapterCandidates) {
    throw 'cross-cli-dispatch adapter not found. Set CROSS_CLI_ADAPTER or install skill-dev.'
}
$adapterPath = @($adapterCandidates)[0]
$adapter = (Resolve-Path -LiteralPath $adapterPath).Path

$scoopPython = if ($env:SCOOP) { Join-Path $env:SCOOP 'apps\python\current\python.exe' } else { $null }
$pythonCandidates = @(
    $env:CROSS_CLI_PYTHON,
    (Get-Command python -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1),
    (Join-Path $HOME 'scoop\apps\python\current\python.exe'),
    (Join-Path $PSScriptRoot '..\..\.tools\scoop\apps\python\current\python.exe'),
    $scoopPython
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
if (-not $pythonCandidates) { throw 'Python is required by cross-cli-dispatch.' }
$pythonPath = @($pythonCandidates)[0]

if ($Arguments.Count -eq 0) {
    throw 'Usage: agent-cli <cli-adapter arguments>; e.g. agent-cli run --backend codex --model gpt-5.3-codex --effort low --prompt "..."'
}

& (Resolve-Path -LiteralPath $pythonPath).Path $adapter @Arguments
exit $LASTEXITCODE
