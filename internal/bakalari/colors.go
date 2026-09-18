package bakalari

import (
	"fmt"
	"github.com/fatih/color"
)

// SubjectColors maps subject abbreviations to ANSI 256 color codes.
type SubjectColors map[string]int

// DefaultSubjectColors returns the built-in color palette.
func DefaultSubjectColors() SubjectColors {
	return SubjectColors{
		"Hv":  135,
		"M":   33,
		"Čj":  34,
		"Prv": 172,
		"Vv":  44,
		"Pč":  160,
		"Tv":  170,
	}
}

// GetColor returns the color code for a subject, falling back to neutral if not found.
func (sc SubjectColors) GetColor(subject string) int {
	if c, ok := sc[subject]; ok {
		return c
	}
	return 244 // Neutral gray
}

// ColorizeSubject returns a string with the subject name formatted with the given background color.
func ColorizeSubject(subject, text string, colorCode int) string {
	// fatih/color doesn't have a direct helper for ANSI 256 background by ID,
	// so we use the raw ANSI sequence combined with color's resetting.
	bg := fmt.Sprintf("\033[48;5;%dm", colorCode)
	fg := "\033[97m" // Bright white
	reset := "\033[0m"
	return fmt.Sprintf("%s%s%s%s", bg, fg, text, reset)
}

// SetupUI sets up the basic colors for the CLI output.
func SetupUI() {
	color.NoColor = false // Force colors if needed
}
