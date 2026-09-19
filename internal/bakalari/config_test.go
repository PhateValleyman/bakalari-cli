package bakalari

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLoadConfigDefaultsAndColors(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "config.toml")
	config := "[general]\nuser01 = \"student\"\n\n[student]\nhost = \"school.example\"\nuser = \"alice\"\npass = \"secret\"\nmax_hours = 0\n\n[colors]\nM = 226\n"Čj" = 34\n"
	if err := os.WriteFile(path, []byte(config), 0600); err != nil {
		t.Fatal(err)
	}

	cfg, err := LoadConfig(path)
	if err != nil {
		t.Fatalf("LoadConfig() error = %v", err)
	}
	if cfg.Colors["M"] != 226 {
		t.Fatalf("M color = %d, want 226", cfg.Colors["M"])
	}

	name, profile, err := cfg.ResolveUser("")
	if err != nil {
		t.Fatalf("ResolveUser() error = %v", err)
	}
	if name != "student" {
		t.Fatalf("profile name = %q, want student", name)
	}
	if profile.MaxHours != 6 {
		t.Fatalf("MaxHours = %d, want 6", profile.MaxHours)
	}
}

func TestSaveTokenPreservesOtherConfig(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "config.toml")
	config := "[general]\nuser01 = \"student\"\n\n[student]\nhost = \"school.example\"\nuser = \"alice\"\npass = \"secret\"\ntoken = \"old\"\n\n[colors]\nM = 226\n"
	if err := os.WriteFile(path, []byte(config), 0600); err != nil {
		t.Fatal(err)
	}

	if err := SaveToken(path, "student", "new-token"); err != nil {
		t.Fatalf("SaveToken() error = %v", err)
	}

	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	text := string(data)
	if !contains(text, "token = \"new-token\"") {
		t.Fatalf("new token not found: %q", text)
	}
	if !contains(text, "pass = \"secret\"") || !contains(text, "[colors]") {
		t.Fatalf("unrelated config changed: %q", text)
	}
}

func contains(s, sub string) bool {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return true
		}
	}
	return false
}
