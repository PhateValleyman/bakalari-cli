package bakalari

import (
	"fmt"
)

// RenderInfo prints a summary of student information.
func RenderInfo(user *UserInfo, absence *AbsenceResponse, marks *MarksResponse) {
	c256 := func(code int) string {
		return fmt.Sprintf("\033[38;5;%dm", code)
	}
	reset := "\033[0m"

	row := func(label, value string, colorCode int) {
		labelColor := c256(colorCode)
		fmt.Printf("%s%-25s%s %s\n", labelColor, label, reset, value)
	}

	// header prints a bold, colored section title (e.g. "=== Absence ===").
	header := func(title string, colorCode int) {
		fmt.Printf("\033[1;38;5;%dm%s%s\n", colorCode, title, reset)
	}

	header("=== Informace o uživateli ===", 39)
	row("Jméno:", user.FullName, 45)
	row("Třída:", user.Class.Name, 45)
	row("Třídní učitel:", user.Class.Teacher.Name, 45)

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
