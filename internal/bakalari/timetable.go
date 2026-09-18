package bakalari

import (
	"fmt"
	"strings"
	"github.com/fatih/color"
)

// RenderTimetable prints a formatted timetable to the console.
func RenderTimetable(data *TimetableResponse, maxHours int, customColors map[string]int) {
	colors := DefaultSubjectColors()
	for k, v := range customColors {
		colors[k] = v
	}

	// Helper for centering text
	center := func(s string, w int) string {
		if len(s) >= w {
			return s[:w]
		}
		total := w - len(s)
		left := total / 2
		right := total - left
		return strings.Repeat(" ", left) + s + strings.Repeat(" ", right)
	}

	// Prepare mapping of subjects and teachers
	subjects := make(map[string]string)
	for _, s := range data.Subjects {
		id := strings.ReplaceAll(s.ID, " ", "")
		subjects[id] = s.Abbrev
		if subjects[id] == "" {
			subjects[id] = s.Name
		}
	}

	teachers := make(map[string]string)
	for _, t := range data.Teachers {
		id := strings.ReplaceAll(t.ID, " ", "")
		parts := strings.Fields(t.Name)
		if len(parts) > 0 {
			teachers[id] = parts[len(parts)-1]
		} else {
			teachers[id] = "?"
		}
	}

	// Prepare hours info
	if maxHours > len(data.Hours) {
		maxHours = len(data.Hours)
	}
	activeHours := data.Hours[:maxHours]

	// Calculate cell width
	maxW := 6
	for _, d := range data.Days {
		for _, a := range d.Atoms {
			sid := strings.ReplaceAll(a.SubjectID, " ", "")
			tid := strings.ReplaceAll(a.TeacherID, " ", "")
			subj := subjects[sid]
			teach := teachers[tid]
			if len(subj) > maxW {
				maxW = len(subj)
			}
			if len(teach) > maxW {
				maxW = len(teach)
			}
		}
	}
	cellW := maxW

	// Headers and Borders
	dayW := 4
	topBorder := "┌" + strings.Repeat("─", dayW) + "┬"
	sepBorder := "├" + strings.Repeat("─", dayW) + "┼"
	botBorder := "└" + strings.Repeat("─", dayW) + "┴"

	for i := 0; i < maxHours; i++ {
		topBorder += strings.Repeat("─", cellW)
		sepBorder += strings.Repeat("─", cellW)
		botBorder += strings.Repeat("─", cellW)
		if i < maxHours-1 {
			topBorder += "┬"
			sepBorder += "┼"
			botBorder += "┴"
		} else {
			topBorder += "┐"
			sepBorder += "┤"
			botBorder += "┘"
		}
	}

	fmt.Println(topBorder)

	// Header rows
	hi := color.New(color.BgWhite, color.FgBlack).SprintFunc()
	hid := color.New(color.BgWhite, color.FgHiBlack).SprintFunc()

	row1 := "│" + hi(center("", dayW)) + "│"
	row2 := "│" + hi(center("", dayW)) + "│"
	row3 := "│" + hi(center("", dayW)) + "│"

	for _, h := range activeHours {
		row1 += hi(center(h.Caption, cellW)) + "│"
		row2 += hid(center(h.BeginTime, cellW)) + "│"
		row3 += hid(center(h.EndTime, cellW)) + "│"
	}
	fmt.Println(row1)
	fmt.Println(row2)
	fmt.Println(row3)
	fmt.Println(sepBorder)

	// Days
	dayNames := map[int]string{1: "Po", 2: "Út", 3: "St", 4: "Čt", 5: "Pá"}

	for i, d := range data.Days {
		if i > 0 {
			fmt.Println(sepBorder)
		}
		
		dn := dayNames[d.DayOfWeek]
		if dn == "" {
			dn = fmt.Sprintf("%d", d.DayOfWeek)
		}

		l1 := "│" + hi(center(dn, dayW)) + "│"
		l2 := "│" + hi(center("", dayW)) + "│"

		for _, h := range activeHours {
			var atom *Atom
			for _, a := range d.Atoms {
				if a.HourID == h.ID {
					atom = &a
					break
				}
			}

			if atom == nil {
				blank := strings.Repeat(" ", cellW)
				l1 += blank + "│"
				l2 += blank + "│"
			} else {
				sid := strings.ReplaceAll(atom.SubjectID, " ", "")
				tid := strings.ReplaceAll(atom.TeacherID, " ", "")
				subj := subjects[sid]
				teach := teachers[tid]
				
				c := colors.GetColor(subj)
				l1 += ColorizeSubject(subj, center(subj, cellW), c) + "│"
				l2 += ColorizeSubject(subj, center(teach, cellW), c) + "│"
			}
		}
		fmt.Println(l1)
		fmt.Println(l2)
	}
	fmt.Println(botBorder)
}
