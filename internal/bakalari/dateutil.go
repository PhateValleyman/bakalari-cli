package bakalari

import "time"

// apiDateLayouts lists the date/time layouts observed in the wild across
// different Bakaláři school deployments. The public API is unofficial and
// not every school runs the same backend version, so the exact format of
// date fields (e.g. AbsenceDay.Date) varies more than you'd expect: some
// include a UTC "Z" suffix, some a numeric offset, some neither.
var apiDateLayouts = []string{
	time.RFC3339,               // 2024-01-15T00:00:00+01:00
	"2006-01-02T15:04:05Z0700", // 2024-01-15T00:00:00+0100
	"2006-01-02T15:04:05.999999999Z07:00",
	"2006-01-02T15:04:05.999999999",
	"2006-01-02T15:04:05",
	"2006-01-02",
}

// parseAPIDate tries every known layout in turn and returns the first one
// that parses. If none of them match, it returns the zero time and false so
// callers can decide how to degrade (e.g. print the raw string instead of a
// misleading "01.01.0001").
func parseAPIDate(s string) (time.Time, bool) {
	for _, layout := range apiDateLayouts {
		if t, err := time.Parse(layout, s); err == nil {
			return t, true
		}
	}
	return time.Time{}, false
}
