package bakalari

import (
	"encoding/json"
	"testing"
)

func TestResolveClassNameFromDirectField(t *testing.T) {
	u := &UserInfo{FullName: "Novák Jan"}
	u.Class.Name = "1.A"
	if got := u.ResolveClassName(); got != "1.A" {
		t.Fatalf("ResolveClassName() = %q, want 1.A", got)
	}
}

func TestResolveClassNameFromAbbrevFallback(t *testing.T) {
	u := &UserInfo{FullName: "Novák Jan"}
	u.Class.Abbrev = "1.A"
	if got := u.ResolveClassName(); got != "1.A" {
		t.Fatalf("ResolveClassName() = %q, want 1.A", got)
	}
}

// This is the exact real-world case reported against a live school
// deployment: Class.Name/Abbrev are both empty, but FullName embeds the
// class after a comma.
func TestResolveClassNameFromFullNameComma(t *testing.T) {
	u := &UserInfo{FullName: "Müller Jonáš, 1.A"}
	if got := u.ResolveClassName(); got != "1.A" {
		t.Fatalf("ResolveClassName() = %q, want 1.A", got)
	}
}

func TestResolveClassNameEmptyWhenNothingAvailable(t *testing.T) {
	u := &UserInfo{FullName: "Novák Jan"}
	if got := u.ResolveClassName(); got != "" {
		t.Fatalf("ResolveClassName() = %q, want empty", got)
	}
}

func TestResolveClassTeacherPrefersDirectField(t *testing.T) {
	u := &UserInfo{}
	u.Class.Teacher.Name = "Turková"
	if got := u.ResolveClassTeacher("Nováková"); got != "Turková" {
		t.Fatalf("ResolveClassTeacher() = %q, want Turková", got)
	}
}

func TestResolveClassTeacherFallsBackToClassTeacherField(t *testing.T) {
	u := &UserInfo{}
	u.Class.ClassTeacher.FullName = "Mgr. Turková"
	if got := u.ResolveClassTeacher(""); got != "Mgr. Turková" {
		t.Fatalf("ResolveClassTeacher() = %q, want Mgr. Turková", got)
	}
}

func TestResolveClassTeacherFallsBackToRootObject(t *testing.T) {
	var u UserInfo
	raw := []byte(`{"UserUID":"x","ClassTeacher":{"Name":"Turková"}}`)
	if err := json.Unmarshal(raw, &u); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if got := u.ResolveClassTeacher(""); got != "Turková" {
		t.Fatalf("ResolveClassTeacher() = %q, want Turková", got)
	}
}

func TestResolveClassTeacherFallsBackToRootPlainString(t *testing.T) {
	var u UserInfo
	raw := []byte(`{"UserUID":"x","ClassTeacher":"Turková"}`)
	if err := json.Unmarshal(raw, &u); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if got := u.ResolveClassTeacher(""); got != "Turková" {
		t.Fatalf("ResolveClassTeacher() = %q, want Turková", got)
	}
}

func TestResolveClassTeacherFallsBackToMostCommonTeacherArg(t *testing.T) {
	u := &UserInfo{}
	if got := u.ResolveClassTeacher("Turková"); got != "Turková" {
		t.Fatalf("ResolveClassTeacher() = %q, want Turková (from timetable fallback)", got)
	}
}

func TestMostCommonTeacherName(t *testing.T) {
	tt := &TimetableResponse{
		Teachers: []Teacher{{ID: "T1", Name: "Turková"}, {ID: "T2", Name: "Novák"}},
		Days: []Day{
			{Atoms: []Atom{{TeacherID: "T1"}, {TeacherID: "T1"}, {TeacherID: "T2"}}},
			{Atoms: []Atom{{TeacherID: "T1"}}},
		},
	}
	if got := MostCommonTeacherName(tt); got != "Turková" {
		t.Fatalf("MostCommonTeacherName() = %q, want Turková", got)
	}
}

func TestMostCommonTeacherNameNilTimetable(t *testing.T) {
	if got := MostCommonTeacherName(nil); got != "" {
		t.Fatalf("MostCommonTeacherName(nil) = %q, want empty", got)
	}
}
