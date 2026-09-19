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
	return 244
}

// ansi256RGB converts an ANSI 256-color index to an approximate RGB value.
func ansi256RGB(code int) (int, int, int) {
	if code < 0 {
		code = 0
	}
	if code > 255 {
		code = 255
	}

	palette := [16][3]int{
		{0, 0, 0}, {205, 0, 0}, {0, 205, 0}, {205, 205, 0},
		{0, 0, 238}, {205, 0, 205}, {0, 205, 205}, {229, 229, 229},
		{127, 127, 127}, {255, 0, 0}, {0, 255, 0}, {255, 255, 0},
		{92, 92, 255}, {255, 0, 255}, {0, 255, 255}, {255, 255, 255},
	}
	if code < 16 {
		return palette[code][0], palette[code][1], palette[code][2]
	}

	if code >= 232 {
		v := 8 + (code-232)*10
		return v, v, v
	}

	code -= 16
	r := code / 36
	g := (code / 6) % 6
	b := code % 6
	levels := [6]int{0, 95, 135, 175, 215, 255}
	return levels[r], levels[g], levels[b]
}

// ColorizeSubject returns text with an ANSI 256-color background and readable foreground.
func ColorizeSubject(subject, text string, colorCode int) string {
	r, g, b := ansi256RGB(colorCode)
	// Relative luminance approximation; use black text on bright backgrounds.
	luminance := (299*r + 587*g + 114*b) / 1000
	fg := 97
	if luminance >= 150 {
		fg = 30
	}
	bg := fmt.Sprintf("\033[48;5;%dm", colorCode)
	return fmt.Sprintf("%s\033[%dm%s\033[0m", bg, fg, text)
}

// SetupUI sets up the basic colors for the CLI output.
func SetupUI() {
	color.NoColor = false
}
