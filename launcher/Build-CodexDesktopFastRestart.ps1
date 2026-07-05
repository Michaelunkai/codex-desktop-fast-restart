$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $PSScriptRoot 'Program.cs'
$outputPath = Join-Path $projectRoot 'CodexDesktopFastRestart.exe'
$compilerPath = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'

if (-not (Test-Path -LiteralPath $compilerPath)) {
    $compilerPath = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
}

if (-not (Test-Path -LiteralPath $compilerPath)) {
    throw 'Windows .NET Framework C# compiler was not found.'
}

& $compilerPath /nologo /target:winexe /optimize+ /out:$outputPath $sourcePath
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

Get-Item -LiteralPath $outputPath | Select-Object FullName, Length
