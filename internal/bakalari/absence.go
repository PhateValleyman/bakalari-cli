package bakalari

import (
	"fmt"
	"github.com/fatih/color"
	"time"
)

// RenderAbsence prints a formatted list of absences.
func RenderAbsence(data *AbsenceResponse) {
	bold := color.New(color.Bold).SprintFunc()
	fmt.Println(bold("=== Absence ==="))

	fmt.Println(bold(fmt.Sprintf("\n%-12s  %2s  %7s  %9s  %7s  %7s  %12s",
		"Datum", "Den", "Hodiny", "Zameškáno", "Pozdě", "Dříve", "Nevyřešeno")))
	fmt.Println("---------------------------------------------------------------")

	dayNames := map[time.Weekday]string{
		time.Monday:    "Po",
		time.Tuesday:   "Út",
		time.Wednesday: "St",
		time.Thursday:  "Čt",
		time.Friday:    "Pá",
		time.Saturday:  "So",
		time.Sunday:    "Ne",
	}

	var totalH, totalM, totalL, totalS, totalU int

	for _, a := range data.Absences {
		date, ok := parseAPIDate(a.Date)
		hours := a.Ok + a.Missed + a.Late + a.Soon

		rowColor := color.New(color.FgHiBlack)
		if a.Missed > 0 || a.Unsolved > 0 {
			rowColor = color.New(color.FgWhite)
		}

		dateText := a.Date // Fall back to the raw value if we couldn't parse it.
		dayText := "?"
		if ok {
			dateText = date.Format("02.01.2006")
			dayText = dayNames[date.Weekday()]
		}

		fmt.Printf("%-12s  %2s  %7d  %9d  %7d  %7d  %12d\n",
			rowColor.Sprint(dateText),
			rowColor.Sprint(dayText),
			hours, a.Missed, a.Late, a.Soon, a.Unsolved)

		totalH += hours
		totalM += a.Missed
		totalL += a.Late
		totalS += a.Soon
		totalU += a.Unsolved
	}

	fmt.Println("---------------------------------------------------------------")
	fmt.Printf("%-12s  %2s  %7d  %9d  %7d  %7d  %12d\n",
		bold("CELKEM"), "", totalH, totalM, totalL, totalS, totalU)
}
