package main

import (
	"log"
	"os"
	"path/filepath"

	"github.com/phatevalleyman/bakalari-cli/internal/bakalari"
)

// setupClient loads the config file, resolves the requested (or default)
// user profile, and builds a ready-to-use API client with caching
// configured. Every data command (rozvrh, ukoly, znamky, absence, info)
// needs exactly this, so it lived as near-identical copy-pasted code in
// each command before being pulled out here.
func setupClient() (client *bakalari.Client, cfg *bakalari.Config, configPath, profileName string, profile bakalari.Profile) {
	configPath = configFile
	if configPath == "" {
		configPath = os.Getenv("BAKALARI_CONFIG")
	}

	cfg, err := bakalari.LoadConfig(configPath)
	if err != nil {
		log.Fatalf("Failed to load config: %v", err)
	}

	profileName, profile, err = cfg.ResolveUser(userProfile)
	if err != nil {
		log.Fatalf("Failed to resolve user: %v", err)
	}

	client = bakalari.NewClient(profile.Host)
	client.Token = profile.Token
	client.Profile = profileName
	client.CacheDir = cfg.General.CacheDir
	if client.CacheDir == "" {
		home, _ := os.UserHomeDir()
		client.CacheDir = filepath.Join(home, ".cache", "bakalari-cli")
	}

	return client, cfg, configPath, profileName, profile
}

// persistTokenIfLoggedIn writes a freshly obtained token back to disk after
// bakalari.FetchWithLoginFallback had to perform a fresh login.
func persistTokenIfLoggedIn(loggedIn bool, client *bakalari.Client, cfg *bakalari.Config, configPath, profileName string, profile *bakalari.Profile) {
	if !loggedIn {
		return
	}
	profile.Token = client.Token
	cfg.Profiles[profileName] = *profile
	if err := bakalari.SaveToken(configPath, profileName, client.Token); err != nil {
		log.Printf("Warning: failed to save token: %v", err)
	}
}
