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

	return profileName, profile, nil
}

// SaveToken updates the token for a specific profile in the config file.
func SaveToken(path, profileName, token string) error {
	// In a real implementation, we'd use a TOML library that preserves comments
	// or perform a surgical update like the bash version.
	return fmt.Errorf("SaveToken not fully implemented for Go yet")
}
