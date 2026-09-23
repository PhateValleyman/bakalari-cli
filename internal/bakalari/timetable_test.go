package bakalari

import "testing"

func TestChangeMarker(t *testing.T) {
	cases := map[string]string{
		"Added": "+",
		"Removed": "×",
		"Canceled": "×",
		"RoomChanged": "R",
		"Substitution": "S",
		"Unknown": "!",
	}
	for input, want := range cases {
		if got := changeMarker(input); got != want {
			t.Errorf("changeMarker(%q) = %q, want %q", input, got, want)
		}
	}
}

func TestDayTypeLabel(t *testing.T) {
	cases := map[string]string{
		"": "",
		"WorkDay": "",
		"Weekend": "vík",
		"Celebration": "svát",
		"Holiday": "práz",
		"DirectorDay": "řel",
		"Undefined": "?",
	}
	for dayType, want := range cases {
		if got := dayTypeLabel(Day{DayType: dayType}); got != want {
			t.Errorf("dayTypeLabel(%q) = %q, want %q", dayType, got, want)
		}
	}
}

func TestTimetableChangeDecoding(t *testing.T) {
	change := &TimetableChange{ChangeType: "Canceled", Description: "Volno"}
	atom := Atom{HourID: 4, Change: change}
	if atom.Change == nil || atom.Change.ChangeType != "Canceled" {
		t.Fatal("timetable change was not retained")
	}
}