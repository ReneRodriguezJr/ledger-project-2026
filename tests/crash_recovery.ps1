#requires -Version 5.1
<#
Run from PowerShell after `alr build`:
  alr exec -- powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\crash_recovery.ps1
Only the Ledger child is killed. Every run gets its own empty test directory.
#>
param(
    [int]$TestKey = 1,
    [int]$TestValue = 100,
    [ValidateRange(1, 120)][int]$TimeoutSeconds = 10
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$LedgerExe = Join-Path $ProjectRoot 'bin/ledger.exe'
if (-not (Test-Path -LiteralPath $LedgerExe -PathType Leaf)) {
    $LedgerExe = Join-Path $ProjectRoot 'bin/ledger'
}
if (-not (Test-Path -LiteralPath $LedgerExe -PathType Leaf)) {
    Write-Host 'FAIL: Ledger executable not found. Run alr build first.'
    exit 1
}

$RunName = 'crash-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N')
$RunDir = Join-Path (Join-Path $ProjectRoot 'test-output') $RunName
[void](New-Item -ItemType Directory -Path $RunDir -Force)
$Expected = "$TestKey $TestValue"  # Independent oracle, known BEFORE the crash.
$Expected | Set-Content -LiteralPath (Join-Path $RunDir 'expected.txt') -Encoding UTF8
$Report = New-Object 'System.Collections.Generic.List[string]'
$Children = New-Object 'System.Collections.Generic.List[object]'
$TimeoutMs = $TimeoutSeconds * 1000
$TestExit = 1

function Report-Line([string]$Line) {
    Write-Host $Line
    $Report.Add($Line)
}

function Start-Ledger([string]$Name, [string]$Command, [bool]$Crash = $false) {
    $Info = New-Object System.Diagnostics.ProcessStartInfo
    $Info.FileName = $LedgerExe
    $Info.WorkingDirectory = $RunDir
    $Info.Arguments = $Command
    $Info.UseShellExecute = $false
    $Info.CreateNoWindow = $true
    $Info.RedirectStandardOutput = $true
    $Info.RedirectStandardError = $true
    # Do not inherit an accidental crash setting into recovery or inspection.
    $Info.EnvironmentVariables.Remove('LEDGER_CRASH_POINT')
    if ($Crash) { $Info.EnvironmentVariables['LEDGER_CRASH_POINT'] = 'after_wal_persist' }
    $Process = New-Object System.Diagnostics.Process
    $Process.StartInfo = $Info
    [void]$Process.Start()
    $Child = [pscustomobject]@{
        Name = $Name
        Process = $Process
        Output = $Process.StandardOutput.ReadToEndAsync()
        ErrorOutput = $Process.StandardError.ReadToEndAsync()
    }
    $Children.Add($Child)
    return $Child
}

function Wait-Ledger($Child) {
    if (-not $Child.Process.WaitForExit($TimeoutMs)) {
        throw "$($Child.Name) timed out."
    }
    if ($Child.Process.ExitCode -ne 0) {
        throw "$($Child.Name) exited with code $($Child.Process.ExitCode). Check its error log."
    }
    return $Child.Output.GetAwaiter().GetResult()
}

try {
    Report-Line 'Starting with an empty test database.'
    Report-Line "Requested write: $Expected"
    $Writer = Start-Ledger 'write' "demo-write $TestKey $TestValue" $true
    $ReadyPath = Join-Path $RunDir 'crash.ready'
    $StorePath = Join-Path $RunDir 'store.txt'
    $Clock = [System.Diagnostics.Stopwatch]::StartNew()
    while (-not (Test-Path -LiteralPath $ReadyPath -PathType Leaf)) {
        if ($Writer.Process.HasExited) { throw 'Ledger exited before reaching the crash point.' }
        if ($Clock.ElapsedMilliseconds -ge $TimeoutMs) { throw 'Crash point was not reached in time.' }
        Start-Sleep -Milliseconds 25
    }
    if ($Writer.Process.HasExited) { throw 'Ledger did not stay paused at the crash point.' }
    if (-not (Test-Path -LiteralPath (Join-Path $RunDir 'wal.txt') -PathType Leaf)) {
        throw 'Crash point was reached without a WAL file.'
    }
    if (Test-Path -LiteralPath $StorePath) { throw 'Storage was updated BEFORE the crash.' }

    Report-Line 'Crash point reached: WAL closed; storage has not been updated.'
    $Writer.Process.Kill()  # Abrupt OS process termination; no Ada cleanup.
    if (-not $Writer.Process.WaitForExit($TimeoutMs)) { throw 'Ledger did not terminate.' }
    if ($Writer.Process.ExitCode -eq 0) { throw 'Ledger exited normally instead of being killed.' }
    if (Test-Path -LiteralPath $StorePath) { throw 'Storage was updated before Ledger was killed.' }
    Report-Line 'Ledger forcibly terminated.'

    $Recovery = Start-Ledger 'recovery' 'demo-recover'
    [void](Wait-Ledger $Recovery)
    Report-Line 'Ledger restarted; WAL replay completed.'

    $Inspection = Start-Ledger 'inspection' 'demo-dump'
    $Actual = (Wait-Ledger $Inspection).Trim()
    $Actual | Set-Content -LiteralPath (Join-Path $RunDir 'actual.txt') -Encoding UTF8
    Report-Line "Expected: $Expected"
    Report-Line "Recovered: $Actual"
    if ($Actual -cne $Expected) { throw 'Recovered state does not match the independent oracle.' }
    $TestExit = 0
}
catch {
    Report-Line "FAIL: $($_.Exception.Message)"
}
finally {
    # Preserve files and child logs on success AND failure. Clean up only
    # the exact processes this test started; never kill by process name.
    foreach ($Child in $Children) {
        try {
            if (-not $Child.Process.HasExited) {
                $Child.Process.Kill()
                if (-not $Child.Process.WaitForExit($TimeoutMs)) { throw 'Cleanup timed out.' }
            }
            $Child.Output.GetAwaiter().GetResult() |
                Set-Content -LiteralPath (Join-Path $RunDir ($Child.Name + '.out.txt')) -Encoding UTF8
            $Child.ErrorOutput.GetAwaiter().GetResult() |
                Set-Content -LiteralPath (Join-Path $RunDir ($Child.Name + '.err.txt')) -Encoding UTF8
            Report-Line "$($Child.Name) exit code: $($Child.Process.ExitCode)"
            $Child.Process.Dispose()
        }
        catch {
            Report-Line "FAIL: could not collect all diagnostics: $($_.Exception.Message)"
            $TestExit = 1
        }
    }
    if ($TestExit -eq 0) {
        Report-Line 'PASS: record recovered after the injected process crash.'
    }
    Report-Line "Evidence: $RunDir"
    $Report | Set-Content -LiteralPath (Join-Path $RunDir 'report.txt') -Encoding UTF8
}
exit $TestExit
