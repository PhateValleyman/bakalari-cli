package bakalari

import (
	"fmt"
	"github.com/fatih/color"
)

// RenderMarks prints a formatted list of grades.
func RenderMarks(data *MarksResponse) {
	fmt.Println(color.New(color.Bold).Sprint("=== Známky ==="))

	for _, s := range data.Subjects {
		avg := s.AverageText
		if avg == "" {
			avg = "-"
		}

		fmt.Printf("[%s] průměr: %s\n", color.New(color.FgCyan).Sprint(s.Subject.Abbrev), avg)

		for _, m := range s.Marks {
			markText := m.MarkText
			if markText == "" {
				markText = "-"
			}

			newMark := ""
			if m.IsNew {
				newMark = color.New(color.FgHiRed, color.Bold).Sprint("  *NOVÁ*")
			}

			date := m.Date
			if len(date) > 10 {
				date = date[:10]
			}
			fmt.Printf("  %-2s  %-20s  %-10s  váha: %d%s\n",
				color.New(color.FgYellow).Sprint(markText),
				m.Caption,
				date,
				m.Weight,
				newMark)
		}
	}
}
