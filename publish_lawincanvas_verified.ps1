param(
    [string]$ProductionRoot = "$env:USERPROFILE\Desktop\lawin canvas",
    [switch]$FullBatch
)

$ErrorActionPreference = "Stop"
$Owner="winwinlawin"; $Master="Lawincanvas002"
$Work=Join-Path $env:TEMP "Lawincanvas_AR_Batch"

if (!(Get-Command git -ErrorAction SilentlyContinue)) { throw "Git not found." }
if (!(Get-Command gh -ErrorAction SilentlyContinue)) { throw "GitHub CLI (gh) not found." }
gh auth status | Out-Host
if ($LASTEXITCODE -ne 0) { throw "GitHub CLI is not authenticated." }

$root=(Resolve-Path $ProductionRoot).Path
$folders=@(Get-ChildItem -LiteralPath $root -Directory | Where-Object { $_.Name -match '^LC\d{3}(?:\s+.*)?$' } | Sort-Object Name)
if (!$folders) { throw "No LC folders found under $root" }
if (!$FullBatch) { $folders=@($folders | Select-Object -First 1); Write-Host "TEST MODE: $($folders[0].Name)" -ForegroundColor Yellow }
else { Write-Host "FULL BATCH: $($folders.Count) LC folders found" -ForegroundColor Cyan }

if ($folders.Count -ne 54 -and $FullBatch) { throw "Expected 54 LC folders, found $($folders.Count). Nothing was deployed." }
if (Test-Path $Work) { Remove-Item $Work -Recurse -Force }; New-Item $Work -ItemType Directory -Force | Out-Null
$report=Join-Path $Work "batch_report.txt"; "Lawin Canvas AR Batch Report - $(Get-Date)" | Set-Content $report -Encoding UTF8
$success=0; $failed=0

foreach($f in $folders){
  $id=([regex]::Match($f.Name,'^LC\d{3}')).Value
  $ar=Join-Path $f.FullName 'AR'; $mind=Join-Path $ar "$id.mind"; $mp4=Join-Path $ar "$id.mp4"
  $repo="$Owner/$id"; $site=Join-Path $Work $id
  Write-Host "`n===== $id =====" -ForegroundColor Cyan
  try {
    if (!(Test-Path $mind -PathType Leaf)) { throw "$id missing $mind" }
    if (!(Test-Path $mp4 -PathType Leaf)) { throw "$id missing $mp4" }
    if (Test-Path $site) { Remove-Item $site -Recurse -Force }
    git clone --depth 1 "https://github.com/$Owner/$Master.git" $site | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "$id could not clone master template" }
    Remove-Item (Join-Path $site '.git') -Recurse -Force -ErrorAction SilentlyContinue
    Get-ChildItem $site -Recurse -File | Where-Object { $_.Extension -in '.html','.js','.css','.json','.txt' } | ForEach-Object {
      $p=$_.FullName; $s=Get-Content $p -Raw -Encoding UTF8; Set-Content $p ($s.Replace('LC002',$id)) -Encoding UTF8
    }
    $td=Join-Path $site 'assets\targets'; $vd=Join-Path $site 'assets\videos'; New-Item $td,$vd -ItemType Directory -Force | Out-Null
    Get-ChildItem $td -File -ErrorAction SilentlyContinue | Remove-Item -Force
    Get-ChildItem $vd -File -ErrorAction SilentlyContinue | Remove-Item -Force
    Copy-Item $mind (Join-Path $td "$id.mind") -Force; Copy-Item $mp4 (Join-Path $vd "$id.mp4") -Force
    $index=Join-Path $site 'index.html'; $app=Join-Path $site 'app.js'
    if (!(Test-Path $index) -or !(Test-Path $app)) { throw "$id template files missing" }
    $ix=Get-Content $index -Raw -Encoding UTF8; $ap=Get-Content $app -Raw -Encoding UTF8
    if ($ix -match 'LC002' -or $ap -match 'LC002') { throw "$id still contains LC002" }
    if ($ix -notmatch [regex]::Escape("$id.mind") -or $ix -notmatch [regex]::Escape("$id.mp4")) { throw "$id references are wrong" }
    Set-Location $site; git init -b main | Out-Null; git config user.name 'winwinlawin'; git config user.email 'hustleonlyguyz@gmail.com'; git add .; git commit -m "Deploy $id AR site" | Out-Null
    gh repo view $repo *> $null; $exists=($LASTEXITCODE -eq 0)
    if (!$exists) { gh repo create $repo --public --source . --remote origin --push | Out-Null }
    else { git remote add origin "https://github.com/$repo.git"; git push --force origin main | Out-Null }
    if ($LASTEXITCODE -ne 0) { throw "$id push failed" }
    gh api --method POST "repos/$repo/pages" -f 'source[branch]=main' -f 'source[path]=/' *> $null
    gh repo view $repo *> $null; if ($LASTEXITCODE -ne 0) { throw "$id repo verification failed" }
    gh api "repos/$repo/contents/assets/targets/$id.mind" *> $null; if ($LASTEXITCODE -ne 0) { throw "$id mind verification failed" }
    gh api "repos/$repo/contents/assets/videos/$id.mp4" *> $null; if ($LASTEXITCODE -ne 0) { throw "$id mp4 verification failed" }
    "SUCCESS $id" | Tee-Object $report -Append; Write-Host "SUCCESS $id" -ForegroundColor Green; $success++
  } catch { "FAILED $id : $($_.Exception.Message)" | Tee-Object $report -Append; Write-Host "FAILED $id : $($_.Exception.Message)" -ForegroundColor Red; $failed++ }
}

Write-Host "`nBATCH COMPLETE" -ForegroundColor Cyan; Write-Host "SUCCESS: $success / $($folders.Count)" -ForegroundColor Green; Write-Host "FAILED: $failed / $($folders.Count)" -ForegroundColor Red; Write-Host "REPORT: $report" -ForegroundColor Yellow
if ($failed -gt 0) { throw "$failed item(s) failed. Batch is NOT complete." }
if ($FullBatch -and $success -ne 54) { throw "Verification failed: expected 54 successful deployments." }
Write-Host "VERIFIED: $success / $($folders.Count)" -ForegroundColor Green
