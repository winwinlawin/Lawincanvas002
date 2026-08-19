param(
    [string]$ProductionRoot = "$env:USERPROFILE\Desktop\lawin canvas",
    [switch]$FullBatch
)

$ErrorActionPreference = "Stop"
$Owner = "winwinlawin"
# LC002 IS THE MASTER TEMPLATE. LC001 IS LEFT ALONE.
$Master = "Lawincanvas002"
$FirstGenerated = 3
$LastGenerated = 54
$ExpectedGenerated = $LastGenerated - $FirstGenerated + 1
$Work = Join-Path $env:TEMP "Lawincanvas_AR_Batch"

function Require-Command([string]$Name) {
    if (!(Get-Command $Name -ErrorAction SilentlyContinue)) { throw "$Name not found in PATH." }
}

Require-Command "git"
Require-Command "gh"

gh auth status | Out-Host
if ($LASTEXITCODE -ne 0) { throw "GitHub CLI is not authenticated. Run: gh auth login" }

if (!(Test-Path -LiteralPath $ProductionRoot -PathType Container)) {
    throw "Production root not found: $ProductionRoot"
}
$root = (Resolve-Path -LiteralPath $ProductionRoot).Path

# Select only LC003 through LC054. LC001 is intentionally ignored.
$folders = @(Get-ChildItem -LiteralPath $root -Directory |
    ForEach-Object {
        $m = [regex]::Match($_.Name, '^LC(\d{3})(?:\s+.*)?$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($m.Success) {
            [pscustomobject]@{
                Folder = $_
                Number = [int]$m.Groups[1].Value
            }
        }
    } |
    Where-Object { $_.Number -ge $FirstGenerated -and $_.Number -le $LastGenerated } |
    Sort-Object Number |
    ForEach-Object { $_.Folder })

if (!$folders) { throw "No LC003-LC054 folders found directly under $root" }

if (!$FullBatch) {
    # TEST MODE always tests LC003 first. LC001 is never selected.
    $test = @($folders | Where-Object { $_.Name -match '^LC003(?:\s+.*)?$' } | Select-Object -First 1)
    if ($test.Count -ne 1) { throw "TEST MODE requires the LC003 folder." }
    $folders = $test
    Write-Host "TEST MODE: $($folders[0].Name)" -ForegroundColor Yellow
} else {
    Write-Host "FULL BATCH: $($folders.Count) LC003-LC054 folders found" -ForegroundColor Cyan
    if ($folders.Count -ne $ExpectedGenerated) {
        throw "Expected exactly $ExpectedGenerated folders (LC003-LC054), found $($folders.Count). Nothing was deployed."
    }
}

if (Test-Path $Work) { Remove-Item $Work -Recurse -Force }
New-Item $Work -ItemType Directory -Force | Out-Null
$report = Join-Path $Work "batch_report.txt"
"Lawin Canvas AR Batch Report - $(Get-Date)" | Set-Content $report -Encoding UTF8
"Production root: $root" | Add-Content $report -Encoding UTF8
"Master template: $Master" | Add-Content $report -Encoding UTF8
"Generated range: LC003-LC054" | Add-Content $report -Encoding UTF8
"Folders selected: $($folders.Count)" | Add-Content $report -Encoding UTF8

$success = 0
$failed = 0

foreach ($f in $folders) {
    $idMatch = [regex]::Match($f.Name, '^LC(\d{3})', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (!$idMatch.Success) {
        "FAILED $($f.Name) : LC number could not be read" | Tee-Object $report -Append
        $failed++
        continue
    }
    $id = "LC$($idMatch.Groups[1].Value)".ToUpperInvariant()

    Write-Host "`n===== $id ($($f.Name)) =====" -ForegroundColor Cyan

    try {
        # Find AR folder case-insensitively.
        $arFolders = @(Get-ChildItem -LiteralPath $f.FullName -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ieq 'ar' })
        if ($arFolders.Count -ne 1) {
            throw "$id AR folder problem: expected exactly 1 folder named AR/ar, found $($arFolders.Count)"
        }
        $ar = $arFolders[0].FullName

        # Find exactly one REAL .mind and one .mp4 file. A .mind.txt file is NOT accepted.
        $mindFiles = @(Get-ChildItem -LiteralPath $ar -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -ieq '.mind' })
        $mp4Files = @(Get-ChildItem -LiteralPath $ar -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -ieq '.mp4' })

        if ($mindFiles.Count -ne 1) {
            throw "$id .mind problem in $ar : expected exactly 1 real .mind file, found $($mindFiles.Count). Check that the file is not .mind.txt."
        }
        if ($mp4Files.Count -ne 1) {
            throw "$id .mp4 problem in $ar : expected exactly 1 .mp4 file, found $($mp4Files.Count)"
        }

        $mind = $mindFiles[0].FullName
        $mp4 = $mp4Files[0].FullName
        Write-Host "AR folder : $ar" -ForegroundColor DarkGray
        Write-Host "MIND file : $($mindFiles[0].Name)" -ForegroundColor DarkGray
        Write-Host "MP4 file  : $($mp4Files[0].Name)" -ForegroundColor DarkGray

        $repo = "$Owner/$id"
        $site = Join-Path $Work $id

        # ALWAYS clone LC002 as the master. LC002 itself is never overwritten by this batch.
        if (Test-Path $site) { Remove-Item $site -Recurse -Force }
        git clone --depth 1 "https://github.com/$Owner/$Master.git" $site | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "$id could not clone master template $Master" }
        Remove-Item (Join-Path $site '.git') -Recurse -Force -ErrorAction SilentlyContinue

        # Replace the master ID with the generated ID everywhere in text assets.
        Get-ChildItem $site -Recurse -File |
            Where-Object { $_.Extension -in '.html','.js','.css','.json','.txt' } |
            ForEach-Object {
                $p = $_.FullName
                $s = Get-Content $p -Raw -Encoding UTF8
                Set-Content $p ($s.Replace('LC002', $id)) -Encoding UTF8
            }

        $td = Join-Path $site 'assets\targets'
        $vd = Join-Path $site 'assets\videos'
        New-Item $td,$vd -ItemType Directory -Force | Out-Null
        Get-ChildItem $td -File -ErrorAction SilentlyContinue | Remove-Item -Force
        Get-ChildItem $vd -File -ErrorAction SilentlyContinue | Remove-Item -Force
        Copy-Item -LiteralPath $mind -Destination (Join-Path $td "$id.mind") -Force
        Copy-Item -LiteralPath $mp4 -Destination (Join-Path $vd "$id.mp4") -Force

        $index = Join-Path $site 'index.html'
        $app = Join-Path $site 'app.js'
        if (!(Test-Path $index) -or !(Test-Path $app)) { throw "$id template files missing" }
        $ix = Get-Content $index -Raw -Encoding UTF8
        $ap = Get-Content $app -Raw -Encoding UTF8
        if ($ix -match 'LC002' -or $ap -match 'LC002') { throw "$id still contains LC002 in generated text files" }
        if ($ix -notmatch [regex]::Escape("$id.mind") -or $ix -notmatch [regex]::Escape("$id.mp4")) {
            throw "$id generated index references are wrong"
        }
        if (!(Test-Path (Join-Path $td "$id.mind")) -or !(Test-Path (Join-Path $vd "$id.mp4"))) {
            throw "$id generated assets were not copied correctly"
        }

        Set-Location $site
        git init -b main | Out-Null
        git config user.name 'winwinlawin'
        git config user.email 'hustleonlyguyz@gmail.com'
        git add .
        git commit -m "Deploy $id AR site" | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "$id local git commit failed" }

        gh repo view $repo *> $null
        $exists = ($LASTEXITCODE -eq 0)
        if (!$exists) {
            gh repo create $repo --public --source . --remote origin --push | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "$id repository creation/push failed" }
        } else {
            git remote add origin "https://github.com/$repo.git"
            git push --force origin main | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "$id existing repository update failed" }
        }

        # Enable Pages only when it is not already enabled.
        gh api "repos/$repo/pages" *> $null
        if ($LASTEXITCODE -ne 0) {
            gh api --method POST "repos/$repo/pages" -f 'source[branch]=main' -f 'source[path]=/' *> $null
            if ($LASTEXITCODE -ne 0) { throw "$id GitHub Pages setup failed" }
        }

        gh repo view $repo *> $null
        if ($LASTEXITCODE -ne 0) { throw "$id repository verification failed" }
        gh api "repos/$repo/contents/assets/targets/$id.mind" *> $null
        if ($LASTEXITCODE -ne 0) { throw "$id .mind verification failed on GitHub" }
        gh api "repos/$repo/contents/assets/videos/$id.mp4" *> $null
        if ($LASTEXITCODE -ne 0) { throw "$id .mp4 verification failed on GitHub" }

        "SUCCESS $id | folder=$($f.Name) | ar=$ar | mind=$($mindFiles[0].Name) | mp4=$($mp4Files[0].Name) | master=$Master" | Tee-Object $report -Append
        Write-Host "SUCCESS $id" -ForegroundColor Green
        $success++
    }
    catch {
        "FAILED $id : $($_.Exception.Message)" | Tee-Object $report -Append
        Write-Host "FAILED $id : $($_.Exception.Message)" -ForegroundColor Red
        $failed++
    }
}

Write-Host "`n==============================" -ForegroundColor Cyan
Write-Host "BATCH COMPLETE" -ForegroundColor Cyan
Write-Host "SUCCESS: $success / $($folders.Count)" -ForegroundColor Green
Write-Host "FAILED : $failed / $($folders.Count)" -ForegroundColor Red
Write-Host "REPORT : $report" -ForegroundColor Yellow
Write-Host "==============================" -ForegroundColor Cyan

if ($failed -gt 0) { throw "$failed item(s) failed. Batch is NOT complete." }
if ($FullBatch -and $success -ne $ExpectedGenerated) { throw "Verification failed: expected $ExpectedGenerated successful deployments." }
Write-Host "VERIFIED: $success / $($folders.Count)" -ForegroundColor Green
