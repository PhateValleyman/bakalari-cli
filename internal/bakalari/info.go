package bakalari

import (
	"fmt"
)

// RenderInfo prints a summary of student information. timetable is optional
// (pass nil if unavailable) and is only used as a last-resort fallback to
// guess the class teacher when the user-info API doesn't expose one
// directly — see UserInfo.ResolveClassTeacher.
func RenderInfo(user *UserInfo, absence *AbsenceResponse, marks *MarksResponse, timetable *TimetableResponse) {
	c256 := func(code int) string {
		return fmt.Sprintf("\033[38;5;%dm", code)
	}
	reset := "\033[0m"

	row := func(label, value string, colorCode int) {
		if value == "" {
			value = "-"
		}
		labelColor := c256(colorCode)
		fmt.Printf("%s%-25s%s %s\n", labelColor, label, reset, value)
	}

	// header prints a bold, colored section title (e.g. "=== Absence ===").
	header := func(title string, colorCode int) {
		fmt.Printf("\033[1;38;5;%dm%s%s\n", colorCode, title, reset)
	}

	header("=== Informace o uživateli ===", 39)
	row("Jméno:", user.FullName, 45)
	row("Třída:", user.ResolveClassName(), 45)
	row("Třídní učitel:", user.ResolveClassTeacher(MostCommonTeacherName(timetable)), 45)

	if absence != nil {
		var totalM, totalU int
		for _, a := range absence.Absences {
			totalM += a.Missed
			totalU += a.Unsolved
		}

		fmt.Println()
		header("=== Docházka ===", 39)
		row("Zameškané hodiny:", fmt.Sprintf("%d", totalM+totalU), 208)
		row("Omluvené hodiny:", fmt.Sprintf("%d", totalM), 40)
		row("Neomluvené / nevyřešené:", fmt.Sprintf("%d", totalU), 196)
	}

	if marks != nil {
		fmt.Println()
		header("=== Průměry podle předmětů ===", 39)
		for _, s := range marks.Subjects {
			if s.AverageText != "" {
				fmt.Printf("%s%-25s%s %s\n", c256(226), s.Subject.Abbrev, reset, s.AverageText)
			}
		}
	}
}
