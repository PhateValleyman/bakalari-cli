package main

import "testing"

// TestAllExpectedCommandsAreRegistered guards against a command file
// existing (rozvrh.go, ukoly.go, ...) without actually wiring itself into
// rootCmd via `func init() { rootCmd.AddCommand(...) }`. That exact mistake
// slipped through once already (ukoly/znamky silently vanished from
// `bakalari --help` after a refactor) because a missing registration
// doesn't cause a build failure - the command file just compiles and does
// nothing. This test makes that failure loud instead of silent.
func TestAllExpectedCommandsAreRegistered(t *testing.T) {
	want := []string{"rozvrh", "ukoly", "znamky", "absence", "info", "cache"}

	got := make(map[string]bool)
	for _, c := range rootCmd.Commands() {
		got[c.Name()] = true
	}

	for _, name := range want {
		if !got[name] {
			t.Errorf("command %q is not registered on rootCmd (missing rootCmd.AddCommand in an init()?)", name)
		}
	}
}
