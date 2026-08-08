# Objavljuje novi update paket za PosMarket.
#
# Redom: spakuje zip, izracuna SHA-256, napravi GitHub release sa tagom v<verzija>,
# pa tek onda osvezi latest.json. Taj redosled je bitan - manifest nikad ne sme da
# pokazuje na asset koji jos ne postoji.
#
# Probni prolaz:  .\publish-update.ps1 -Verzija 3.0.2 -Izvor C:\build\izmene
# Stvarna objava: .\publish-update.ps1 -Verzija 3.0.2 -Izvor C:\build\izmene -Apply
param(
    [Parameter(Mandatory=$true)][string]$Verzija,
    [Parameter(Mandatory=$true)][string]$Izvor,
    [string]$MinVerzija,
    [string]$Napomene = "",
    [switch]$Obavezan,
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'

$Repo      = 'atr-milenijum/posmarket-updates'
$Proizvod  = 'posmarket'
$Prefiks   = 'mps-posmarket'
$Koren     = $PSScriptRoot
$Manifest  = Join-Path $Koren 'latest.json'

# --- provere ------------------------------------------------------------------

if ($Verzija -notmatch '^\d+\.\d+(\.\d+)?$') {
    throw "Verzija '$Verzija' nije u obliku 3.0.2"
}
if (-not (Test-Path -LiteralPath $Izvor)) {
    throw "Izvorni folder ne postoji: $Izvor"
}
$fajlovi = Get-ChildItem -LiteralPath $Izvor -Recurse -File
if ($fajlovi.Count -eq 0) {
    throw "Izvorni folder je prazan: $Izvor"
}

$stari = Get-Content -LiteralPath $Manifest -Raw | ConvertFrom-Json
if ([version]$Verzija -le [version]$stari.verzija) {
    throw "Verzija $Verzija nije novija od trenutne $($stari.verzija) u latest.json"
}
if (-not $MinVerzija) { $MinVerzija = $stari.min_verzija }
if ($MinVerzija -notmatch '^\d+\.\d+(\.\d+)?$') {
    throw "MinVerzija '$MinVerzija' nije u obliku 3.0.0"
}

$tag = "v$Verzija"
gh release view $tag --repo $Repo 1>$null 2>$null
if ($LASTEXITCODE -eq 0) { throw "Release $tag vec postoji na $Repo" }

# --- pakovanje ----------------------------------------------------------------

$imeZipa = "$Prefiks-v$Verzija-update.zip"
$zip = Join-Path $Koren $imeZipa
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }

Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory(
    (Resolve-Path -LiteralPath $Izvor).Path, $zip,
    [System.IO.Compression.CompressionLevel]::Optimal, $false)

$hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLower()
$vel  = (Get-Item -LiteralPath $zip).Length

Write-Output ""
Write-Output "paket    : $imeZipa"
Write-Output "verzija  : $($stari.verzija)  ->  $Verzija"
Write-Output "min      : $MinVerzija"
Write-Output "obavezan : $([bool]$Obavezan)"
Write-Output "velicina : $([math]::Round($vel/1KB,1)) KB"
Write-Output "sha256   : $hash"
Write-Output "fajlova  : $($fajlovi.Count)"
$fajlovi | ForEach-Object {
    Write-Output ("   " + $_.FullName.Substring((Resolve-Path -LiteralPath $Izvor).Path.Length + 1))
}

if (-not $Apply) {
    Write-Output ""
    Write-Output "Probni prolaz. Zip je napravljen ali nista nije objavljeno."
    Write-Output "Pokreni sa -Apply da objavis."
    return
}

# --- objava -------------------------------------------------------------------

$telo = if ($Napomene) { $Napomene } else { "Update paket za PosMarket $Verzija." }
gh release create $tag $zip --repo $Repo --title $tag --notes $telo
if ($LASTEXITCODE -ne 0) { throw "gh release create nije uspeo - manifest nije diran" }

$novi = [ordered]@{
    proizvod    = $Proizvod
    verzija     = $Verzija
    datum       = (Get-Date -Format 'yyyy-MM-dd')
    url         = "https://github.com/$Repo/releases/download/$tag/$imeZipa"
    sha256      = $hash
    velicina    = $vel
    min_verzija = $MinVerzija
    obavezan    = [bool]$Obavezan
    napomene    = $Napomene
}
$json = ($novi | ConvertTo-Json -Depth 5) + "`n"
[System.IO.File]::WriteAllText($Manifest, $json, (New-Object System.Text.UTF8Encoding($false)))

git -C $Koren add latest.json
git -C $Koren commit -q -m "PosMarket $Verzija"
git -C $Koren push -q origin main
if ($LASTEXITCODE -ne 0) { throw "push manifesta nije uspeo - release POSTOJI, rucno osvezi latest.json" }

Remove-Item -LiteralPath $zip -Force
Write-Output ""
Write-Output "Objavljeno: https://github.com/$Repo/releases/tag/$tag"
Write-Output "Manifest osvezen na $Verzija"
