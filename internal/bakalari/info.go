package bakalari

import (
	"fmt"
	"github.com/fatih/color"
)

// RenderInfo prints a summary of student information.
func RenderInfo(user *UserInfo, absence *AbsenceResponse, marks *MarksResponse) {
	c256 := func(code int) string {
		return fmt.Sprintf("\033[38;5;%dm", code)
	}
	reset := "\033[0m"
	bold := color.New(color.Bold).SprintFunc()
	
	row := func(label, value string, colorCode int) {
		labelColor := c256(colorCode)
		fmt.Printf("%s%-25s%s %s\n", labelColor, label, reset, value)
	}

	fmt.Printf("%s%s=== Informace o uživateli ===%s\n", bold(""), c256(39), reset)
	row("Jméno:", user.FullName, 45)
	row("Třída:", user.Class.Name, 45)
	row("Třídní učitel:", user.Class.Teacher.Name, 45)

	if absence != nil {
		var totalM, totalU int
		for _, a := range absence.Absences {
			totalM += a.Missed
			totalU += a.Unsolved
		}
		
		fmt.Printf("\n%s%s=== Docházka ===%s\n", bold(""), c256(39), reset)
		row("Zameškané hodiny:", fmt.Sprintf("%d", totalM+totalU), 208)
		row("Omluvené hodiny:", fmt.Sprintf("%d", totalM), 40)
		row("Neomluvené / nevyřešené:", fmt.Sprintf("%d", totalU), 196)
	}

	if marks != nil {
		fmt.Printf("\n%s%s=== Průměry podle předmětů ===%s\n", bold(""), c256(39), reset)
		for _, s := range marks.Subjects {
			if s.AverageText != "" {
				fmt.Printf("%s%-25s%s %s\n", c256(226), s.Subject.Abbrev, reset, s.AverageText)
			}
		}
	}
}
