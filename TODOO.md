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

- [x] Přidán `tests/mock_server.py` + `tests/smoke.sh` pro lokální API mock
      a smoke testy pro `rozvrh.sh`, `ukoly.sh`, `znamky.sh` a `absence.sh`.
- [x] `shellcheck` do CI (GitLab CI) + smoke test workflow – ať se regrese chytí automaticky.
- [x] Podpora více škol/účtů zároveň přes profily `userNN` a volbu `--user`.
- [x] Přidat `znamky.sh` (známky) a `absence.sh` (absence) – oba skripty
      používají sdílený login/config vzor a API v3 endpointy.
- [x] Sjednotit chybové kódy exit statusů: `2` = konfigurace/argumenty,
      `3` = síť/API transport, `4` = neplatná data.
- [x] Lokálně cachovat poslední platný rozvrh a při offline provozu jej automaticky použít.
- [x] Přidat `info.sh` – profil studenta, třída, třídní učitel, docházka a průměry podle předmětů.
- [x] Přidat validovanou offline cache pro všechny datové moduly.
- [x] Přidat `cache` modul pro výpis cesty, seznam souborů a bezpečné vyčištění cache.
- [x] Sjednotit normalizaci URL školy a přidat timeouty pro přihlašovací požadavek.
- [x] Přidat interaktivní editor `config` s oddělenými rozsahy `users` a `global`.
- [x] Přidat navigaci `← Zpět`, výchozí hodnoty a přímé ANSI náhledy barev.

## Příprava na přechod na Go

Cílem je, aby přechod na Go nebyl "přepsat vše najednou", ale postupný:

- [x] Zafixovat formát `config.toml` tak, jak je teď (sekce `[general]` +
      sekce podle domény školy) – v Go půjde načíst pomocí
      `github.com/BurntSushi/toml` beze změny formátu pro uživatele.
- [x] Vyextrahovat JSON tvary odpovědí Bakalářů (login, timetable,
      homeworks, marks, absence, user info) do `docs/api-notes.md` jako podklad pro Go
      struktury (`struct { ... }` + `json:"..."` tagy).
- [x] Navrhnout `internal/bakalari` balíček v Go s rozhraním, které
      odpovídá dnešním bash funkcím v `lib/common.sh`:
      - `Login(school, user, pass) (Token, error)`
      - `FetchTimetable(token) (Timetable, error)`
      - `FetchHomeworks(token) (Homeworks, error)`
      - `LoadConfig(path) (Config, error)` / `SaveToken(...)`
- [x] Zvolit CLI framework (`cobra` nebo `urfave/cli`) tak, aby
      `bakalari rozvrh` a `bakalari ukoly` byly subpříkazy jednoho binárku,
      ne dva samostatné skripty.
- [x] Barevný výstup v Go přes `fatih/color` nebo `lipgloss` – zachovat
      stejnou barevnou paletu předmětů jako dnes v `awk` části `rozvrh.sh`.
- [ ] Cross-compile pro `arm64` (Redmi Note 11, Shield tablet) a `mipsel`
      (ZyXEL NSA320) – ověřit, že binárka bez problémů běží i na starším
      Android 5.1 / ffp.
- [/] Až bude Go verze na paritě s bash verzí (rozvrh + úkoly + notifikace),
      bash skripty přesunout do `legacy/` a `README.md` přepsat na Go verzi
      jako primární.
      (Aktuálně implementováno: rozvrh, úkoly, známky, absence, info, cache)

## Nápady (bez závazku)

- [ ] Widget/shortcut pro Termux:Widget spouštějící `rozvrh.sh`.
- [ ] Export rozvrhu do `.ics` (kalendář).
- [ ] Souhrnná notifikace i pro nové známky, ne jen úkoly.
