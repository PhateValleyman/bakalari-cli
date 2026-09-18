# bakalari-cli

Malé shellové nástroje pro práci s API systému Bakaláři z terminálu / Termuxu.

- **`rozvrh.sh`** – vypíše barevný rozvrh přímo do terminálu.
- **`ukoly.sh`** – zkontroluje nesplněné domácí úkoly a (na Androidu v Termuxu) o nich pošle notifikaci přes `termux-notification`.
- **`znamky.sh`** – zobrazí známky a průměry.
- **`absence.sh`** – zobrazí souhrn absence a přehled podle předmětů.

Oba skripty sdílejí stejnou konfiguraci, přihlašovací logiku a barevný výstup přes `lib/common.sh`.

## Požadavky

- `bash` (skripty používají `#!/usr/bin/env bash`, funguje tedy jak v Termuxu, tak na ZyXEL NSA320 s ffp, tak na běžném Linuxu)
- [`jq`](https://jqlang.org/)
- `curl`
- `awk` (ideálně `gawk`, běžný `awk` funguje jako fallback)

### Instalace závislostí

```bash
# Termux (Android)
pkg install jq curl gawk

# Debian/Ubuntu
sudo apt install jq curl gawk

# ffp na ZyXEL NSA320
ipkg install jq curl gawk
```

## Instalace

```bash
git clone https://github.com/PhateValleyman/bakalari-cli.git
cd bakalari-cli
chmod +x rozvrh.sh ukoly.sh

mkdir -p ~/.config/bakalari
cp config.toml.example ~/.config/bakalari/config.toml
$EDITOR ~/.config/bakalari/config.toml
```

## Konfigurace

Konfigurace žije v `~/.config/bakalari/config.toml` (cestu lze přebít proměnnou prostředí `BAKALARI_CONFIG`). Soubor **není** součástí repozitáře (viz `.gitignore`) — obsahuje přihlašovací údaje.

```toml
[general]
school     = "zssumava.bakalari.cz"   # doména Bakalářů bez "https://"
max_hours  = 6                          # kolik hodin zobrazit v rozvrhu

[colors]
# Volitelné barvy předmětů v ANSI 256-color paletě (0–255).
# Pokud položku neuvedeš, použije se vestavěná výchozí barva.
Hv  = 135
M   = 33
Čj  = 34
Prv = 172
Vv  = 44
Pč  = 160
Tv  = 170

[zssumava.bakalari.cz]
user  = "your_username"
pass  = "your_password"
TOKEN = ""                             # doplní se automaticky po přihlášení
```

### Barvy předmětů

Sekce `[colors]` je volitelná. `rozvrh.sh` používá ANSI 256-color paletu. Každý předmět může mít vlastní číslo barvy od `0` do `255`.

Pokud například chceš změnit pouze matematiku a český jazyk:

```toml
[colors]
M  = 226
Čj = 39
```

Všechny ostatní předměty automaticky zachovají původní výchozí barvy. Pokud `[colors]` vůbec není, vzhled rozvrhu se nezmění.

Výchozí barvy jsou:

| Předmět | ANSI 256 |
|---|---:|
| Hv | 135 |
| M | 33 |
| Čj | 34 |
| Prv | 172 |
| Vv | 44 |
| Pč | 160 |
| Tv | 170 |

Neznámý předmět, který nemá vlastní konfiguraci ani vestavěnou barvu, používá neutrální barvu `244`.

Přístupový token se po prvním přihlášení uloží zpět do konfigurace a při dalších spuštěních se skripty nejdřív pokusí použít jej — teprve když je neplatný nebo chybí, proběhne nové přihlášení k Bakalářům.

## Použití

```bash
./rozvrh.sh          # barevný rozvrh
./ukoly.sh           # kontrola nesplněných úkolů (+ notifikace v Termuxu)
./znamky.sh          # známky a průměry
./absence.sh         # absence

./rozvrh.sh --help
./ukoly.sh  --help

# Use another configured school/account without changing [general].
./rozvrh.sh --school another-school.example
./ukoly.sh --school another-school.example
```

### Testy

Projekt obsahuje lokální API mock a smoke testy bez nutnosti přihlašovat se ke skutečnému účtu:

```bash
# Run the complete local smoke test suite.
bash tests/smoke.sh
```

CI automaticky spouští `shellcheck` nad shellovými skripty a následně stejné smoke testy.

```

### Automatizace (Termux crond / cron)

```cron
*/30 7-16 * * 1-5  bash ~/bakalari-cli/ukoly.sh >> ~/bakalari-cli.log 2>&1
```

## Struktura projektu

```
bakalari-cli/
├── rozvrh.sh            # zobrazení rozvrhu
├── ukoly.sh             # kontrola domácích úkolů + notifikace
├── znamky.sh            # známky a průměry
├── absence.sh           # absence
├── lib/
│   └── common.sh        # sdílená konfigurace, login, barvy, logování
├── config.toml.example  # vzor konfigurace
├── docs/
│   └── api-notes.md     # použité tvary odpovědí API v3
└── TODOO.md             # plánované úpravy a roadmapa (mj. přechod na Go)
```

Veškerá logika společná pro více skriptů (čtení configu, přihlašování k Bakalářům, ukládání tokenu, barevné logovací funkce a načítání konfigurace barev) patří do `lib/common.sh`. Nový skript by měl tento soubor sourcovat místo toho, aby si logiku duplikoval.

## Bezpečnost

- `config.toml` obsahuje heslo v čistém textu — udržujte mu rozumná práva (`chmod 600 ~/.config/bakalari/config.toml`) a nikdy jej necommitujte.
- Pokud jste dřív používali starší verzi `ukoly.sh` s přihlašovacími údaji natvrdo v kódu, **změňte si heslo k Bakalářům** a údaje přesuňte do `config.toml`.

## Roadmap

Plánované úpravy a příprava na přepis do Go jsou v [`TODOO.md`](TODOO.md).
