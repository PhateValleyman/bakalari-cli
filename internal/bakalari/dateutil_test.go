package bakalari

import "testing"

func TestParseAPIDateAcceptsKnownVariants(t *testing.T) {
	cases := []string{
		"2024-01-15T00:00:00+01:00",
		"2024-01-15T00:00:00+0100",
		"2024-01-15T00:00:00.1234567+01:00",
		"2024-01-15T00:00:00",
		"2024-01-15T00:00:00Z",
		"2024-01-15",
	}
	for _, s := range cases {
		got, ok := parseAPIDate(s)
		if !ok {
			t.Errorf("parseAPIDate(%q) failed to parse", s)
			continue
		}
		if got.Year() != 2024 || got.Month() != 1 || got.Day() != 15 {
			t.Errorf("parseAPIDate(%q) = %v, want 2024-01-15", s, got)
		}
	}
}

func TestParseAPIDateRejectsGarbage(t *testing.T) {
	if _, ok := parseAPIDate("not a date"); ok {
		t.Fatal("parseAPIDate(garbage) unexpectedly succeeded")
	}
}
