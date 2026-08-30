$ErrorActionPreference = "Stop"
Set-Location -LiteralPath $PSScriptRoot

$Runtime = Join-Path $PSScriptRoot "_runtime"
$AppPathFile = Join-Path $Runtime "APP_PATH.txt"
$Temp = Join-Path $Runtime "_patch_update"
$Backup = Join-Path $Runtime "_patch_backup"
$VersionFile = Join-Path $Runtime "PATCH_VERSION.txt"
$BaseUrl = "https://raw.githubusercontent.com/demon-mami/AutoFisher-VRC/main"

function Fail([string]$Message) {
    Write-Host ""
    Write-Host "[ERROR] $Message" -ForegroundColor Red
    [void](Read-Host "Enter")
    exit 1
}

function Download-File([string]$Url, [string]$OutFile) {
    $Parent = Split-Path -Parent $OutFile
    New-Item -ItemType Directory -Force -Path $Parent | Out-Null

    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($null -ne $curl) {
        & $curl.Source -L --fail --retry 3 --retry-delay 1 --output $OutFile $Url
        if ($LASTEXITCODE -eq 0) {
            return
        }
        Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
    }

    $ProgressPreference = "SilentlyContinue"
    Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
}

try {
    Write-Host "============================================================"
    Write-Host " AutoFisher-VRC - Patch Update"
    Write-Host "============================================================"
    Write-Host ""

    if (-not (Test-Path -LiteralPath $AppPathFile)) {
        Fail "_runtime\APP_PATH.txt がありません。v1.5 Runtimeのフォルダで実行してください。"
    }

    $RelativeExe = (Get-Content -LiteralPath $AppPathFile -Raw).Trim()
    if ([string]::IsNullOrWhiteSpace($RelativeExe)) {
        Fail "APP_PATH.txt が空です。"
    }

    $Exe = Join-Path $Runtime $RelativeExe
    if (-not (Test-Path -LiteralPath $Exe)) {
        Fail ("day123本体EXEが見つかりません: " + $Exe)
    }

    $ExeDir = Split-Path -Parent $Exe
    $PatchDir = Join-Path $ExeDir "patch"

    if (Test-Path -LiteralPath $Temp) {
        Remove-Item -LiteralPath $Temp -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $Temp | Out-Null

    Write-Host "[1/4] GitHub Canonical patchを取得..."
    $Files = @(
        "patch/core/pd_controller.py",
        "patch/core/control_executor.py",
        "patch/core/control_backends.py",
        "patch/gui/app.py"
    )

    foreach ($Rel in $Files) {
        $Url = "$BaseUrl/$Rel"
        $Out = Join-Path $Temp $Rel
        Download-File $Url $Out

        if (-not (Test-Path -LiteralPath $Out)) {
            Fail ("取得失敗: " + $Rel)
        }
        if ((Get-Item -LiteralPath $Out).Length -lt 200) {
            Fail ("取得ファイルが不正です: " + $Rel)
        }
    }

    $VersionTemp = Join-Path $Temp "VERSION"
    Download-File "$BaseUrl/VERSION" $VersionTemp
    if (-not (Test-Path -LiteralPath $VersionTemp)) {
        Fail "VERSIONの取得に失敗しました。"
    }
    $Version = (Get-Content -LiteralPath $VersionTemp -Raw).Trim()

    Write-Host "[2/4] 現在のpatchを1世代だけバックアップ..."
    if (Test-Path -LiteralPath $Backup) {
        Remove-Item -LiteralPath $Backup -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $Backup | Out-Null
    if (Test-Path -LiteralPath $PatchDir) {
        Copy-Item -Path (Join-Path $PatchDir "*") -Destination $Backup -Recurse -Force
    }

    Write-Host "[3/4] AutoFisher-VRC patchを反映..."
    New-Item -ItemType Directory -Force -Path (Join-Path $PatchDir "core") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $PatchDir "gui") | Out-Null

    Copy-Item -LiteralPath (Join-Path $Temp "patch\core\pd_controller.py") `
        -Destination (Join-Path $PatchDir "core\pd_controller.py") -Force
    Copy-Item -LiteralPath (Join-Path $Temp "patch\core\control_executor.py") `
        -Destination (Join-Path $PatchDir "core\control_executor.py") -Force
    Copy-Item -LiteralPath (Join-Path $Temp "patch\core\control_backends.py") `
        -Destination (Join-Path $PatchDir "core\control_backends.py") -Force
    Copy-Item -LiteralPath (Join-Path $Temp "patch\gui\app.py") `
        -Destination (Join-Path $PatchDir "gui\app.py") -Force

    foreach ($Rel in $Files) {
        $Installed = Join-Path $ExeDir $Rel
        if (-not (Test-Path -LiteralPath $Installed)) {
            Fail ("反映後検証に失敗: " + $Rel)
        }
        if ((Get-Item -LiteralPath $Installed).Length -lt 200) {
            Fail ("反映後ファイルが不正: " + $Rel)
        }
    }

    Write-Host "[4/4] 更新状態を保存..."
    $Version | Set-Content -LiteralPath $VersionFile -Encoding UTF8
    Remove-Item -LiteralPath $Temp -Recurse -Force

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host ("[更新完了] AutoFisher-VRC " + $Version) -ForegroundColor Green
    Write-Host "2_RUN.bat で起動してください。"
    Write-Host "============================================================" -ForegroundColor Green
    [void](Read-Host "Enter")
}
catch {
    Fail $_.Exception.Message
}
