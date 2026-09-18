package bakalari

import (
	"fmt"
	"time"
	"github.com/fatih/color"
)

// RenderAbsence prints a formatted list of absences.
func RenderAbsence(data *AbsenceResponse) {
	fmt.Printf("%s=== Absence ===%s\n", color.New(color.Bold).SprintFunc()(""), "")
	
	bold := color.New(color.Bold).SprintFunc()
	fmt.Printf("\n%s%-12s  %2s  %7s  %9s  %7s  %7s  %12s%s\n", 
		color.New(color.Bold).Sprint(""), "Datum", "Den", "Hodiny", "Zameškáno", "Pozdě", "Dříve", "Nevyřešeno", "")
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
		date, _ := time.Parse("2006-01-02T15:04:05", a.Date)
		hours := a.Ok + a.Missed + a.Late + a.Soon
		
		rowColor := color.New(color.FgHiBlack)
		if a.Missed > 0 || a.Unsolved > 0 {
			rowColor = color.New(color.FgWhite)
		}
		
		fmt.Printf("%-12s  %2s  %7d  %9d  %7d  %7d  %12d\n",
			rowColor.Sprint(date.Format("02.01.2006")),
			rowColor.Sprint(dayNames[date.Weekday()]),
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
