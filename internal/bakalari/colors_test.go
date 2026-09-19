package bakalari

import "testing"

func TestAnsi256RGB(t *testing.T) {
	tests := []struct {
		code    int
		r, g, b int
	}{
		{0, 0, 0, 0},
		{15, 255, 255, 255},
		{16, 0, 0, 0},
		{21, 0, 0, 255},
		{231, 255, 255, 255},
		{232, 8, 8, 8},
		{255, 238, 238, 238},
	}

	for _, tt := range tests {
		r, g, b := ansi256RGB(tt.code)
		if r != tt.r || g != tt.g || b != tt.b {
			t.Fatalf("ansi256RGB(%d) = (%d,%d,%d), want (%d,%d,%d)", tt.code, r, g, b, tt.r, tt.g, tt.b)
		}
	}
}
