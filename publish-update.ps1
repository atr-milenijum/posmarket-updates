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
# Puna putanja iz istog izvora kao FullName na stavkama, da se relativne
# putanje racunaju tacno i kad je prosledjeno kratko 8.3 ime.
$baza = (Get-Item -LiteralPath $Izvor).FullName.TrimEnd('\')
$fajlovi = Get-ChildItem -LiteralPath $baza -Recurse -File
if ($fajlovi.Count -eq 0) {
    throw "Izvorni folder je prazan: $baza"
}

# Povuci pre svega ostalog. Bez ovoga se provera verzije radi nad zastarelim
# latest.json ako je neko drugi u medjuvremenu objavio, a push bi pukao tek na
# kraju - posle sto je release vec napravljen.
git -C $Koren pull --rebase -q origin main
if ($LASTEXITCODE -ne 0) {
    throw "git pull nije uspeo. Resi to pre objave - inace radis nad zastarelim manifestom."
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
# Preko cmd-a, da PowerShell 5.1 ne pretvori stderr od gh u terminating error.
cmd /c "gh release view $tag --repo $Repo >nul 2>&1"
$vecPostoji = ($LASTEXITCODE -eq 0)
if ($vecPostoji) { throw "Release $tag vec postoji na $Repo" }

# --- pakovanje ----------------------------------------------------------------

$imeZipa = "$Prefiks-v$Verzija-update.zip"
$zip = Join-Path $Koren $imeZipa
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

# Rucno pakovanje umesto CreateFromDirectory, jer ono na .NET Frameworku upisuje
# putanje sa obrnutom kosom crtom. ZIP standard trazi '/', a neki alati inace
# naprave fajl doslovno nazvan "Reports\racun.rpt" umesto podfoldera.
$tok = $null
$arh = $null
try {
    $tok = [System.IO.File]::Create($zip)
    $arh = New-Object System.IO.Compression.ZipArchive($tok, [System.IO.Compression.ZipArchiveMode]::Create)
    foreach ($f in $fajlovi) {
        $rel = $f.FullName.Substring($baza.Length).TrimStart('\').Replace('\', '/')
        $ulaz = $arh.CreateEntry($rel, [System.IO.Compression.CompressionLevel]::Optimal)
        $izlazni = $ulaz.Open()
        $ulazni  = [System.IO.File]::OpenRead($f.FullName)
        try { $ulazni.CopyTo($izlazni) } finally { $ulazni.Dispose(); $izlazni.Dispose() }
    }
} finally {
    if ($arh) { $arh.Dispose() }
    if ($tok) { $tok.Dispose() }
}

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
    Write-Output ("   " + $_.FullName.Substring($baza.Length).TrimStart('\'))
}

if (-not $Apply) {
    Write-Output ""
    Write-Output "Probni prolaz. Zip je napravljen ali nista nije objavljeno."
    Write-Output "Pokreni sa -Apply da objavis."
    exit 0
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
