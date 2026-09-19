package bakalari

import (
	"fmt"
	"github.com/fatih/color"
)

// RenderHomeworks prints a formatted list of homeworks.
func RenderHomeworks(data *HomeworksResponse) {
	fmt.Println(color.New(color.Bold).Sprint("=== Domácí úkoly ==="))

	count := 0
	for _, hw := range data.Homeworks {
		if hw.IsDone {
			continue
		}

		count++
		status := color.New(color.FgRed).Sprint(" [ ] ")
		subject := color.New(color.FgCyan).Sprintf("[%s]", hw.Subject.Abbrev)
		date := color.New(color.FgYellow).Sprint(hw.DateEnd)

		fmt.Printf("%s %s %s: %s\n", status, subject, date, hw.Content)
	}

	if count == 0 {
		fmt.Println(color.New(color.FgHiBlack).Sprint("(žádné nesplněné úkoly)"))
	}
}
