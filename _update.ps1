$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot

$Runtime = Join-Path $PSScriptRoot '_runtime'
$AppPathFile = Join-Path $Runtime 'APP_PATH.txt'
$VersionFile = Join-Path $Runtime 'PATCH_VERSION.txt'
$BaseUrl = 'https://raw.githubusercontent.com/demon-mami/AutoFisher-VRC/main'

if (-not (Test-Path -LiteralPath $AppPathFile)) {
    Write-Host '[ERROR] _runtime\APP_PATH.txt がありません。' -ForegroundColor Red
    Read-Host 'Enter'
    exit 1
}

$RelativeExe = (Get-Content -LiteralPath $AppPathFile -Raw).Trim()
$Exe = Join-Path $Runtime $RelativeExe

if (-not (Test-Path -LiteralPath $Exe)) {
    Write-Host ('[ERROR] day123本体EXEがありません: ' + $Exe) -ForegroundColor Red
    Read-Host 'Enter'
    exit 1
}

$ExeDir = Split-Path -Parent $Exe
$PatchDir = Join-Path $ExeDir 'patch'
$CoreDir = Join-Path $PatchDir 'core'
$GuiDir = Join-Path $PatchDir 'gui'

New-Item -ItemType Directory -Force -Path $CoreDir | Out-Null
New-Item -ItemType Directory -Force -Path $GuiDir | Out-Null

Write-Host '[1/4] pd_controller.py'
Invoke-WebRequest -Uri ($BaseUrl + '/patch/core/pd_controller.py') -OutFile (Join-Path $CoreDir 'pd_controller.py') -UseBasicParsing

Write-Host '[2/4] control_executor.py'
Invoke-WebRequest -Uri ($BaseUrl + '/patch/core/control_executor.py') -OutFile (Join-Path $CoreDir 'control_executor.py') -UseBasicParsing

Write-Host '[3/4] control_backends.py'
Invoke-WebRequest -Uri ($BaseUrl + '/patch/core/control_backends.py') -OutFile (Join-Path $CoreDir 'control_backends.py') -UseBasicParsing

Write-Host '[4/4] minimal GUI'
Invoke-WebRequest -Uri ($BaseUrl + '/patch/gui/app.py') -OutFile (Join-Path $GuiDir 'app.py') -UseBasicParsing

$Required = @(
    (Join-Path $CoreDir 'pd_controller.py'),
    (Join-Path $CoreDir 'control_executor.py'),
    (Join-Path $CoreDir 'control_backends.py'),
    (Join-Path $GuiDir 'app.py')
)

foreach ($File in $Required) {
    if (-not (Test-Path -LiteralPath $File)) {
        Write-Host ('[ERROR] 反映失敗: ' + $File) -ForegroundColor Red
        Read-Host 'Enter'
        exit 1
    }
    if ((Get-Item -LiteralPath $File).Length -lt 200) {
        Write-Host ('[ERROR] ファイルサイズ異常: ' + $File) -ForegroundColor Red
        Read-Host 'Enter'
        exit 1
    }
}

$Version = (Invoke-WebRequest -Uri ($BaseUrl + '/VERSION') -UseBasicParsing).Content.Trim()
Set-Content -LiteralPath $VersionFile -Value $Version -Encoding UTF8

Write-Host ''
Write-Host ('[更新完了] AutoFisher-VRC ' + $Version) -ForegroundColor Green
Write-Host '2_RUN.bat で起動してください。'
Read-Host 'Enter'
