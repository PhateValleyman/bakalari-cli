# TODOO

Poznámky, plánované opravy a příprava na přepis do Golangu.
(Ano, "TODOO" – název podle zadání, ne překlep.)

## Právě opraveno

- [x] **Regrese, kterou jsem sám způsobil v předchozím kole refaktoringu:**
      při přepisu `ukoly.go`/`znamky.go` na sdílený `FetchWithLoginFallback`
      jsem omylem vynechal `func init() { rootCmd.AddCommand(...) }` →
      oba příkazy se přestaly registrovat a zmizely z `bakalari --help`
      i ze samotného CLI, aniž by to `go build` nějak nahlásil (chybějící
      registrace není chyba kompilace, jen tichá ztráta funkčnosti).
      Opraveno + přidán `cmd/bakalari/main_test.go`
      (`TestAllExpectedCommandsAreRegistered`), který ověří, že všech 6
      příkazů je skutečně navěšeno na `rootCmd` – ověřeno, že bez opravy
      test spolehlivě spadne, takže tahle třída regrese se příště chytí
      v `go test`, ne až na tvém telefonu.

- [x] Reálné hlášené chyby z provozu na Redmi (`bakalari info` a
      `bakalari absence`):
  - `absence.go`: `time.Parse` používal jediný pevný formát
    (`2006-01-02T15:04:05`), který na tvé škole neseděl → všechna data se
    tiše propadla na nulovou hodnotu `time.Time`, což se vykreslilo jako
    `01.01.0001` / `Po` u každého řádku. Přidán `dateutil.go` s
    `parseAPIDate()`, který zkouší několik běžných variant (s/bez
    časové zóny, s/bez desetinných sekund) a při neúspěchu vypíše
    aspoň syrovou hodnotu a `?` místo tichého klamání nulovým datem.
  - `info.go`: `Třída`/`Třídní učitel` byly prázdné, protože skutečná
    odpověď `/api/3/user` je na tvé škole mnohem bohatší (bash cache
    4350 B vs. Go parsovalo jen 112 B z ní) a pole nejsou tam, kde je Go
    struct čekal. `UserInfo` teď zkouší stejný řetězec fallbacků jako
    už dřív fungující `info.sh`: `Class.Name` → `Class.Abbrev` →
    rozparsování `FullName` tvaru `"Příjmení Jméno, Třída"` (přesně tvůj
    případ `"Müller Jonáš, 1.A"`); u učitele navíc `Class.Teacher` →
    `Class.ClassTeacher` → kořenové `ClassTeacher` (objekt i čistý
    string) → a jako poslední záchrana nejčastěji se opakující učitel
    v rozvrhu (`MostCommonTeacherName`), stejně jako to dělá bash.
    Pokud po tomhle bude `Třídní učitel` pořád prázdný, pošli mi prosím
    obsah `~/.cache/bakalari-cli/info-*-user.json` (bash cache, 4350 B) –
    uvidím přesný tvar odpovědi tvé školy a dopíšu poslední fallback.
  - `client.go`: cache soubory Go binárky měly v názvu i schéma
    (`absence-Dzonny-https:__zssumava.bakalari.cz.json`), protože se
    sanitizovalo jen lomítko, ne dvojtečka. Teď se ukládá čistě jako
    `absence-Dzonny-zssumava.bakalari.cz.json` (odpovídá konvenci bash
    nástrojů, i když jde stále o oddělenou cache – sdílení cache mezi
    Go a bash verzí jsem záměrně needěl bez domluvy, protože `info.sh`
    má vlastní `info-*` namespace z důvodu jiných nároků na čerstvost).

- [x] `config_test.go` měl neescapovanou uvozovku kolem `"Čj"` v řetězcovém
      literálu → `go build`/`go vet`/`go test` na celém modulu vůbec neprošly.
      Opraveno, `gofmt -l` je teď na `internal/` a `cmd/` čisté (předtím
      nekonzistentní formátování napříč skoro všemi soubory).
- [x] `internal/bakalari/timetable.go`: `center()` a výpočet šířky sloupců
      počítaly délku textu přes `len()` (bajty) místo počtu znaků → tabulka
      rozvrhu se s diakritikou (`Čj`, `Pč`, `Út`, `Čt`, `Pá`, `Dvořák`, ...)
      rozjížděla nebo se text uřízl uprostřed víceznakového UTF-8 znaku.
      Přepsáno na `utf8.RuneCountInString` / bezpečné ořezávání přes `[]rune`.
- [x] `marks.go`, `absence.go`, `homeworks.go`, `info.go`: nadpisy sekcí
      (`=== Známky ===` apod.) používaly `color.New(color.Bold).SprintFunc()("")`
      – tučně se obalil prázdný řetězec a samotný text zůstal netučný.
      Sjednoceno na jednu `header()`/`bold()` pomocnou funkci na soubor.
- [x] `rozvrh.go`, `ukoly.go`, `znamky.go`, `absence.go`, `info.go` měly
      každý ručně kopírovanou (~25řádkovou) sekvenci
      „zkus fetch → login → retry → fallback na cache → ulož token“.
      Vyextrahováno do `bakalari.FetchWithLoginFallback[T]` (generická
      funkce, `internal/bakalari/fetch.go` + `fetch_test.go`) a
      `cmd/bakalari/common.go` (`setupClient`, `persistTokenIfLoggedIn`).
      Chování je teď garantovaně stejné pro všechny datové příkazy.
- [x] `ukoly.go` míchalo v notifikaci češtinu s angličtinou
      (`"%s and %d more"`) → sjednoceno na češtinu (`"a %d další"`).
- [x] Nová funkce (byl to nápad níž v sekci "Nápady"): `znamky` teď při
      zjištění nových známek (`IsNew`) pošle Android notifikaci stejně
      jako `ukoly` u nesplněných úkolů.
- [x] Go klient měl chybějící `LoadCachedTimetable()` a nešel zkompilovat – doplněn loader cache rozvrhu.
- [x] Go příkazy při nedostupné síti končily chybou po neúspěšném loginu místo použití offline cache – všechny datové příkazy nyní po selhání obnovy tokenu zkusí cache.
- [x] Opravena TOML escapace tokenu v Go klientovi (zpětná lomítka a uvozovky).
- [x] Přidán `make test` a Go test job do GitLab CI (`go test -mod=vendor ./...`).
- [x] Go renderer používá kontrastní černý/bílý text podle jasu ANSI 256 pozadí; přidán regresní test převodu barev.

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
- [x] Cross-compile pro `arm64` (Redmi Note 11) – **ověřeno na reálném
      zařízení** (`bakalari info`/`rozvrh`/`cache` reálně odběhly přes
      Termux). `armv7` (Shield Tablet K1) a `armv5`/GOARM=5 (ZyXEL NSA320,
      ffp) se zatím cross-compilují bez chyby, ale běh na těch dvou
      konkrétních zařízeních ještě nikdo nepotvrdil.
- [/] Až bude Go verze na paritě s bash verzí (rozvrh + úkoly + notifikace),
      bash skripty přesunout do `legacy/` a `README.md` přepsat na Go verzi
      jako primární.
      (Aktuálně implementováno: rozvrh, úkoly, známky, absence, info, cache;
      Go klient nově odděluje online chyby od offline cache a umí atomicky ukládat token.)

## Nápady (bez závazku)

- [x] Widget/shortcut pro Termux:Widget spouštějící `bakalari-cli rozvrh`.
- [ ] Export rozvrhu do `.ics` (kalendář).
- [x] Souhrnná notifikace i pro nové známky, ne jen úkoly. (hotovo v Go i
      bash verzi – `znamky`/`znamky.sh` teď posílají notifikaci stejně jako
      `ukoly`/`ukoly.sh`.)
