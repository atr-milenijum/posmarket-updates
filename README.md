# PosMarket — update paketi

Interni repozitorijum. Ovde se objavljuju inkrementalni update paketi za MPS PosMarket.
Pune instalacije su u [mps-downloads](https://github.com/atr-milenijum/mps-downloads).

## Kako radi

Aplikacija na startu čita **jedan** fajl:

```
https://raw.githubusercontent.com/atr-milenijum/posmarket-updates/main/latest.json
```

Ide preko `raw.githubusercontent.com`, a ne preko GitHub API-ja, jer API ima ograničenje
od 60 zahteva na sat po IP adresi — prodavnica sa više kasa iza jednog rutera bi ga trošila.

```json
{
  "proizvod": "posmarket",
  "verzija": "3.0.2",
  "datum": "2026-08-10",
  "url": "https://github.com/atr-milenijum/posmarket-updates/releases/download/v3.0.2/mps-posmarket-v3.0.2-update.zip",
  "sha256": "a3f5c9...",
  "velicina": 184320,
  "min_verzija": "3.0.0",
  "obavezan": false,
  "napomene": "Ispravka obracuna rabata na nivou stavke"
}
```

| Polje | Značenje |
|---|---|
| `verzija` | verzija koju paket donosi |
| `url` | direktan link na zip; `null` znači da nema objavljenog paketa |
| `sha256` | heš zipa, **obavezno proveriti pre raspakivanja** |
| `min_verzija` | najstarija verzija na koju se paket sme primeniti |
| `obavezan` | ako je `true`, aplikacija ne nastavlja bez update-a |
| `napomene` | tekst za korisnika |

## Odluka u aplikaciji

```
ako url == null            -> nema update-a
ako verzija <= lokalna     -> nema update-a
ako lokalna < min_verzija  -> potrebna puna instalacija, ne primenjuj paket
inace                      -> ponudi update
```

Poređenje verzija ide preko `System.Version`, ne poređenjem stringova — `"3.0.10"` je kao
string manje od `"3.0.9"`.

## Paketi su kumulativni

Svaki paket sadrži **sve što se promenilo od poslednje pune instalacije**, ne razliku u
odnosu na prethodni paket. Klijent na 3.0 i klijent na 3.0.1 skidaju isti paket i oba
završe na istoj verziji. Zato nema lanaca, redosleda primene ni slučaja preskočene verzije.

`min_verzija` govori dokle ta kumulativnost seže. Kad izađe nova puna instalacija,
`min_verzija` se podiže na njenu verziju.

## Struktura zipa

Preslikava install folder, sa relativnim putanjama:

```
mps-posmarket-v3.0.2-update.zip
├── PosMarket.exe
├── LibImg.dll
└── Reports/
    └── racun.rpt
```

## Prvo podešavanje na novom računaru

**1. Pristup.** Nalog mora biti član organizacije `atr-milenijum` sa **Write** dozvolom na
ovom repozitorijumu. Vlasnik dodaje kroz Settings → Collaborators and teams. Bez toga
`gh release create` odbija objavu.

**2. Alati.**

```powershell
winget install Git.Git
winget install GitHub.cli
```

Zatvori pa otvori novi terminal da se PATH osveži.

**3. Prijava.** Svako se prijavljuje **svojim** nalogom, organizacija se ne loguje zasebno:

```powershell
gh auth login
```

GitHub.com → HTTPS → Y za git kredencijale → Login with a web browser.

**4. Git identitet**, ako već nije podešen — ide u commit poruku manifesta:

```powershell
git config --global user.name "Ime Prezime"
git config --global user.email "ime@ms.rs"
```

**5. Kloniraj:**

```powershell
git clone https://github.com/atr-milenijum/posmarket-updates.git
cd posmarket-updates
```

Ako PowerShell odbije da pokrene skriptu zbog ExecutionPolicy:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
```

Važi samo za taj prozor i ne menja podešavanja mašine.

## Kad više ljudi objavljuje

Skripta na početku sama radi `git pull --rebase`, pa nema potrebe da to radiš ručno.
Ako pull pukne, skripta staje **pre** nego što išta objavi — reši konflikt pa pokreni ponovo.

Dva čoveka ne treba da objavljuju istovremeno. Tag verzije je jedinstven, pa će drugi
dobiti grešku „release već postoji", ali je jednostavnije dogovoriti se ko objavljuje.

## Objava nove verzije

```powershell
# probni prolaz - samo prikaze sta bi uradio
.\publish-update.ps1 -Verzija 3.0.2 -Izvor "C:\build\posmarket\izmene" -Napomene "Ispravka rabata"

# stvarna objava
.\publish-update.ps1 -Verzija 3.0.2 -Izvor "C:\build\posmarket\izmene" -Napomene "Ispravka rabata" -Apply
```

`-Izvor` je folder čiji se **sadržaj** pakuje, sa očuvanom strukturom podfoldera.

Skripta redom: spakuje zip, izračuna SHA-256, napravi release sa tagom `v3.0.2`, i tek
onda osveži `latest.json`. Taj redosled je bitan — manifest nikad ne sme da pokazuje na
asset koji još ne postoji.

Dodatne opcije: `-MinVerzija` (podrazumevano se prenosi iz postojećeg manifesta) i
`-Obavezan`.

## Na strani aplikacije

Stvari koje se lako previde:

- **TLS 1.2** — `ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072;` pre
  prvog zahteva. Bez toga .NET ispod 4.6 pokušava TLS 1.0 i GitHub odbija vezu.
- **Provera SHA-256** pre raspakivanja. Prekinut download ume da bude validan ZIP.
- **Raspakuj u temp pa premesti**, nikad direktno preko live foldera.
- **Backup** fajlova koji se menjaju, pre prepisivanja.
- **Provera putanja iz zipa** — ulaz tipa `..\..\Windows\System32\x.dll` mora biti odbijen.
- **`PosMarket.exe` ne može da prepiše sam sebe** dok radi, isto važi za učitane DLL-ove.
  Potreban je zaseban updater proces koji sačeka gašenje aplikacije.
