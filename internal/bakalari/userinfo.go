package bakalari

import (
	"encoding/json"
	"strings"
)

// ResolveClassName returns the student's class (e.g. "1.A"), trying every
// shape we've seen a school's API use, in the same order as the legacy
// bash info.sh: Class.Name, then Class.Abbrev, then finally falling back to
// splitting it out of FullName when the API returns it as "Surname Name,
// Class" (some deployments really do this instead of a separate field).
func (u *UserInfo) ResolveClassName() string {
	if u.Class.Name != "" {
		return u.Class.Name
	}
	if u.Class.Abbrev != "" {
		return u.Class.Abbrev
	}
	if _, class, ok := splitFullNameAndClass(u.FullName); ok {
		return class
	}
	return ""
}

// ResolveClassTeacher returns the class teacher's name, trying every shape
// we've seen a school's API use, in the same order as the legacy bash
// info.sh. mostCommonTeacher is an optional last-resort fallback (pass ""
// if unavailable): some schools don't expose a class teacher field at all,
// so info.sh derives it from whichever teacher appears most often in the
// student's own timetable.
func (u *UserInfo) ResolveClassTeacher(mostCommonTeacher string) string {
	if name := u.Class.Teacher.DisplayName(); name != "" {
		return name
	}
	if name := u.Class.ClassTeacher.DisplayName(); name != "" {
		return name
	}
	if name := resolveRootClassTeacher(u.ClassTeacherRaw); name != "" {
		return name
	}
	return mostCommonTeacher
}

// resolveRootClassTeacher handles the root-level "ClassTeacher" field,
// which on some schools is an object ({"Name": "..."} / {"FullName": "..."})
// and on others is a plain string.
func resolveRootClassTeacher(raw json.RawMessage) string {
	if len(raw) == 0 {
		return ""
	}

	var person NamedPerson
	if err := json.Unmarshal(raw, &person); err == nil {
		if name := person.DisplayName(); name != "" {
			return name
		}
	}

	var plain string
	if err := json.Unmarshal(raw, &plain); err == nil {
		return strings.TrimSpace(plain)
	}

	return ""
}

// splitFullNameAndClass splits a FullName like "Müller Jonáš, 1.A" into the
// name part and the class part. Some Bakaláři deployments return the class
// this way instead of a separate Class.Name/Abbrev field.
func splitFullNameAndClass(fullName string) (name, class string, ok bool) {
	idx := strings.Index(fullName, ",")
	if idx < 0 {
		return fullName, "", false
	}
	name = strings.TrimSpace(fullName[:idx])
	class = strings.TrimSpace(fullName[idx+1:])
	if class == "" {
		return name, "", false
	}
	return name, class, true
}

// MostCommonTeacherName returns the name of the teacher who appears most
// often across the timetable's lessons. Used as a last-resort fallback for
// the class teacher on schools whose API doesn't expose one directly.
func MostCommonTeacherName(tt *TimetableResponse) string {
	if tt == nil {
		return ""
	}

	teacherNames := make(map[string]string, len(tt.Teachers))
	for _, t := range tt.Teachers {
		teacherNames[t.ID] = t.Name
	}

	counts := make(map[string]int)
	for _, d := range tt.Days {
		for _, a := range d.Atoms {
			name := teacherNames[a.TeacherID]
			if name == "" {
				continue
			}
			counts[name]++
		}
	}

	best := ""
	bestCount := 0
	for name, count := range counts {
		if count > bestCount || (count == bestCount && name < best) {
			best = name
			bestCount = count
		}
	}
	return best
}
