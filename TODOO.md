# TODOO

Poznámky, plánované opravy a příprava na přepis do Golangu.
(Ano, "TODOO" – název podle zadání, ne překlep.)

## Právě opraveno

- [x] `ukoly.sh` mělo natvrdo v kódu uživatelské jméno a heslo k Bakalářům –
      přesunuto do `config.toml`, sdíleno s `rozvrh.sh`.
- [x] `rozvrh.sh` a `ukoly.sh` měly každý vlastní (a rozdílnou) logiku pro
      config, login a ukládání tokenu → sjednoceno v `lib/common.sh`.
- [x] `rozvrh.sh` měl natvrdo Termux shebang
      (`#!/data/data/com.termux/files/usr/bin/bash`), takže nešel spustit na
      ZyXEL NSA320 (ffp) ani jinde → `#!/usr/bin/env bash` na obou skriptech.
- [x] `ukoly.sh` se přihlašovalo úplně vždy, i když měl platný token –
      nyní se stejně jako `rozvrh.sh` nejdřív zkusí uložený `TOKEN`.
- [x] Nekonzistentní/nebarevný výstup mezi skripty → jednotné `log_info` /
      `log_warn` / `log_error` / `log_ok` s barvami v `lib/common.sh`.
- [x] Hodnoty `MAX_HOUR` a `SCHOOL` natvrdo v kódu → přesunuty do
      `config.toml` (`[general]`), s výchozími hodnotami jako fallback.
- [x] Chybějící kontrola závislostí (`jq`, `curl`, `awk`) → `require_cmd()`.

## Krátkodobé (bash)

- [ ] Přidat `known.sh` / testovací mock server (viz fake API použité při
      vývoji) jako `tests/` s jednoduchými smoke testy pro `rozvrh.sh`
      a `ukoly.sh`.
- [ ] `shellcheck` do CI (GitHub Actions) – ať se regrese chytí automaticky.
- [ ] Podpora více škol/účtů zároveň (config už to připouští – `[general]`
      + libovolná sekce podle domény – ale skripty zatím berou jen jednu
      `school` z `[general]`; přidat `--school` argument).
- [ ] Přidat `znamky.sh` (známky) a `absence.sh` (absence) – stejný vzor
      jako `ukoly.sh`, jen jiný endpoint a jiné `jq` mapování.
- [ ] Sjednotit chybové kódy exit statusů (dnes všude `exit 1`; do budoucna
      rozlišit např. 2 = chybí config, 3 = chyba sítě, 4 = neplatná data).

## Příprava na přechod na Go

Cílem je, aby přechod na Go nebyl "přepsat vše najednou", ale postupný:

- [ ] Zafixovat formát `config.toml` tak, jak je teď (sekce `[general]` +
      sekce podle domény školy) – v Go půjde načíst pomocí
      `github.com/BurntSushi/toml` beze změny formátu pro uživatele.
- [ ] Vyextrahovat JSON tvary odpovědí Bakalářů (login, timetable,
      homeworks) do `docs/api-notes.md`, aby šly rovnou převést na Go
      struktury (`struct { ... }` + `json:"..."` tagy).
- [ ] Navrhnout `internal/bakalari` balíček v Go s rozhraním, které
      odpovídá dnešním bash funkcím v `lib/common.sh`:
      - `Login(school, user, pass) (Token, error)`
      - `FetchTimetable(token) (Timetable, error)`
      - `FetchHomeworks(token) (Homeworks, error)`
      - `LoadConfig(path) (Config, error)` / `SaveToken(...)`
- [ ] Zvolit CLI framework (`cobra` nebo `urfave/cli`) tak, aby
      `bakalari rozvrh` a `bakalari ukoly` byly subpříkazy jednoho binárku,
      ne dva samostatné skripty.
- [ ] Barevný výstup v Go přes `fatih/color` nebo `lipgloss` – zachovat
      stejnou barevnou paletu předmětů jako dnes v `awk` části `rozvrh.sh`.
- [ ] Cross-compile pro `arm64` (Redmi Note 11, Shield tablet) a `mipsel`
      (ZyXEL NSA320) – ověřit, že binárka bez problémů běží i na starším
      Android 5.1 / ffp.
- [ ] Až bude Go verze na paritě s bash verzí (rozvrh + úkoly + notifikace),
      bash skripty přesunout do `legacy/` a `README.md` přepsat na Go verzi
      jako primární.

## Nápady (bez závazku)

- [ ] Widget/shortcut pro Termux:Widget spouštějící `rozvrh.sh`.
- [ ] Export rozvrhu do `.ics` (kalendář).
- [ ] Souhrnná notifikace i pro nové známky, ne jen úkoly.
