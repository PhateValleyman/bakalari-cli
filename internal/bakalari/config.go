package bakalari

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/BurntSushi/toml"
)

// Config represents the application configuration.
type Config struct {
	General struct {
		CacheDir string            `toml:"cache_dir"`
		Users    map[string]string `toml:"-"` // Handled via raw map to support userNN
	} `toml:"general"`
	Profiles map[string]Profile `toml:"-"`      // Handled via raw map to support dynamic section names
	Colors   map[string]int     `toml:"colors"` // ANSI colors for subjects
}

// Profile represents a single student profile.
type Profile struct {
	Host     string `toml:"host"`
	User     string `toml:"user"`
	Pass     string `toml:"pass"`
	MaxHours int    `toml:"max_hours"`
	Token    string `toml:"token"`
	Name     string `toml:"name"`
	Class    string `toml:"class"`
}

// LoadConfig loads the configuration from the given path.
func LoadConfig(path string) (*Config, error) {
	if path == "" {
		home, _ := os.UserHomeDir()
		path = filepath.Join(home, ".config", "bakalari-cli", "config.toml")
	}

	var raw map[string]interface{}
	if _, err := toml.DecodeFile(path, &raw); err != nil {
		return nil, err
	}

	config := &Config{
		Profiles: make(map[string]Profile),
		Colors:   make(map[string]int),
	}

	// Manual parsing to handle dynamic keys in [general] and profiles
	if general, ok := raw["general"].(map[string]interface{}); ok {
		config.General.Users = make(map[string]string)
		for k, v := range general {
			if k == "cache_dir" {
				config.General.CacheDir, _ = v.(string)
			} else if strings.HasPrefix(k, "user") {
				if username, ok := v.(string); ok {
					config.General.Users[k] = username
				}
			}
		}
	}

	if colors, ok := raw["colors"].(map[string]interface{}); ok {
		for k, v := range colors {
			if val, ok := v.(int64); ok {
				config.Colors[k] = int(val)
			}
		}
	}

	// All other sections are profiles
	for k, v := range raw {
		if k == "general" || k == "colors" {
			continue
		}
		if profileMap, ok := v.(map[string]interface{}); ok {
			var p Profile
			// Simplistic mapping for brevity
			if host, ok := profileMap["host"].(string); ok {
				p.Host = host
			}
			if user, ok := profileMap["user"].(string); ok {
				p.User = user
			}
			if pass, ok := profileMap["pass"].(string); ok {
				p.Pass = pass
			}
			if maxHours, ok := profileMap["max_hours"].(int64); ok {
				p.MaxHours = int(maxHours)
			}
			if token, ok := profileMap["token"].(string); ok {
				p.Token = token
			}
			if name, ok := profileMap["name"].(string); ok {
				p.Name = name
			}
			if class, ok := profileMap["class"].(string); ok {
				p.Class = class
			}
			config.Profiles[k] = p
		}
	}

	return config, nil
}

// ResolveUser returns the profile name and the profile itself for the requested user.
// If requested is empty, it returns the first userNN from [general].
func (c *Config) ResolveUser(requested string) (string, Profile, error) {
	profileName := requested
	if profileName == "" {
		// Find first userNN (numerically sorted)
		var firstKey string
		var minIndex int = -1

		for k, v := range c.General.Users {
			var index int
			fmt.Sscanf(k, "user%d", &index)
			if minIndex == -1 || index < minIndex {
				minIndex = index
				firstKey = v
			}
		}
		profileName = firstKey
	}

	if profileName == "" {
		return "", Profile{}, fmt.Errorf("no user profile found")
	}

	profile, ok := c.Profiles[profileName]
	if !ok {
		return "", Profile{}, fmt.Errorf("profile %s not found", profileName)
	}
	if profile.Host == "" || profile.User == "" {
		return "", Profile{}, fmt.Errorf("profile %s has incomplete configuration", profileName)
	}
	if profile.MaxHours <= 0 {
		profile.MaxHours = 6
	}

	return profileName, profile, nil
}

// SaveToken updates one profile's token while preserving the rest of the TOML file.
func SaveToken(path, profileName, token string) error {
	if path == "" {
		home, _ := os.UserHomeDir()
		path = filepath.Join(home, ".config", "bakalari-cli", "config.toml")
	}

	data, err := os.ReadFile(path)
	if err != nil {
		return fmt.Errorf("read config: %w", err)
	}

	lines := strings.Split(string(data), "\n")
	section := "[" + profileName + "]"
	inProfile := false
	foundProfile := false
	tokenWritten := false

	for i, line := range lines {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "[") && strings.HasSuffix(trimmed, "]") {
			inProfile = trimmed == section
			if inProfile {
				foundProfile = true
			}
			continue
		}
		if !inProfile || !strings.HasPrefix(trimmed, "token") {
			continue
		}
		parts := strings.SplitN(line, "=", 2)
		if len(parts) != 2 {
			continue
		}
		indent := line[:len(line)-len(strings.TrimLeft(line, " \t"))]
		lines[i] = indent + "token = \"" + escapeTOMLString(token) + "\""
		tokenWritten = true
	}

	if !foundProfile {
		return fmt.Errorf("profile %q not found", profileName)
	}

	if !tokenWritten {
		for i, line := range lines {
			if strings.TrimSpace(line) == section {
				lines = append(lines[:i+1], append([]string{"token = \"" + escapeTOMLString(token) + "\"" }, lines[i+1:]...)...)
				break
			}
		}
	}

	tmp, err := os.CreateTemp(filepath.Dir(path), ".config.toml.tmp-*")
	if err != nil {
		return fmt.Errorf("create temporary config: %w", err)
	}
	tmpName := tmp.Name()
	defer os.Remove(tmpName)

	if err := tmp.Chmod(0600); err != nil {
		tmp.Close()
		return fmt.Errorf("set config permissions: %w", err)
	}
	if _, err := tmp.WriteString(strings.Join(lines, "\n")); err != nil {
		tmp.Close()
		return fmt.Errorf("write temporary config: %w", err)
	}
	if err := tmp.Close(); err != nil {
		return fmt.Errorf("close temporary config: %w", err)
	}
	if err := os.Rename(tmpName, path); err != nil {
		return fmt.Errorf("replace config: %w", err)
	}
	return nil
}

func escapeTOMLString(value string) string {
	value = strings.ReplaceAll(value, "\\\\", "\\\\\\\\")
	value = strings.ReplaceAll(value, "\"", "\\\\"")
	return value
}
