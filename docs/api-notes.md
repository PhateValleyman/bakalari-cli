# Bakaláři API notes

Pracovní poznámky k API v3 používanému v bakalari-cli.

## Endpoints

| Funkce | Endpoint | Očekávaný kořen odpovědi |
|---|---|---|
| Login | POST /api/login | access_token |
| Rozvrh | GET /api/3/timetable/actual | Days, Hours, Subjects, Teachers |
| Úkoly | GET /api/3/homeworks | Homeworks |
| Známky | GET /api/3/marks | Subjects[] |
| Absence | GET /api/3/absence/student | Absences[], AbsencesPerSubject[] |\n| User info | GET /api/3/user | UserUID, FullName, Class, UserType, ... |

Všechny GET endpointy používají Authorization: Bearer ACCESS_TOKEN.

## Login

Aktuální CLI používá POST /api/login s client_id=ANDR, grant_type=password, username a password. Očekává JSON s access_token.

## Rozvrh

/api/3/timetable/actual vrací mimo jiné Hours[] (Id, Caption, BeginTime, EndTime), Days[] (DayOfWeek, Atoms[]), Atoms[] (HourId, SubjectId, TeacherId), Subjects[] (Id, Abbrev, Name) a Teachers[] (Id, Name).

ID předmětů a učitelů mohou obsahovat mezery; rozvrh.sh je při mapování normalizuje.

## Úkoly

/api/3/homeworks vrací Homeworks[]. Pro aktuální CLI jsou důležitá pole IsDone, Content, DateEnd a Subject.Abbrev.

## Známky

/api/3/marks vrací Subjects[]. Každý předmět obsahuje Marks[] a objekt Subject.

Důležitá pole známky: MarkDate, Caption, MarkText, SubjectId, Weight, IsPoints, PointsText, MaxPoints a IsNew.

Předmět navíc poskytuje AverageText, TemporaryMark a PointsOnly.

## Absence

/api/3/absence/student vrací PercentageThreshold, Absences[] (denní souhrny: Date, Ok, Missed, Late, Soon, ...) a AbsencesPerSubject[] (SubjectName, LessonsCount, Base, Late, Soon, ...).

AbsencesPerSubject může být prázdné podle oprávnění školy.

## Zdroje

Struktura je odvozena z veřejné analýzy Bakaláři API v3 (bakalari-api/bakalari-api-v3), zejména dokumentace endpointů marks, absence, timetable a homeworks.

Tyto poznámky popisují pouze pole, která projekt skutečně používá; nejsou náhradou za kompletní API dokumentaci.
