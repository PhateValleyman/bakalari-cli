package main

import (
	"log"
	"os"
	"path/filepath"

	"github.com/phatevalleyman/bakalari-cli/internal/bakalari"
	"github.com/spf13/cobra"
)

var rozvrhCmd = &cobra.Command{
	Use:   "rozvrh",
	Short: "Show timetable",
	Run: func(cmd *cobra.Command, args []string) {
		configPath := configFile
		if configPath == "" {
			configPath = os.Getenv("BAKALARI_CONFIG")
		}

		cfg, err := bakalari.LoadConfig(configPath)
		if err != nil {
			log.Fatalf("Failed to load config: %v", err)
		}

		profileName, profile, err := cfg.ResolveUser(userProfile)
		if err != nil {
			log.Fatalf("Failed to resolve user: %v", err)
		}

		client := bakalari.NewClient(profile.Host)
		client.Token = profile.Token
		client.Profile = profileName
		client.CacheDir = cfg.General.CacheDir
		if client.CacheDir == "" {
			home, _ := os.UserHomeDir()
			client.CacheDir = filepath.Join(home, ".cache", "bakalari-cli")
		}

		timetable, err := client.FetchTimetable()
		if err != nil {
			// Try to refresh the token; if the network is unavailable, use cache.
			err = client.Login(profile.User, profile.Pass)
			if err != nil {
				if cached, cacheErr := client.LoadCachedTimetable(); cacheErr == nil {
					log.Printf("Warning: using cached timetable: %v", err)
					bakalari.RenderTimetable(cached, profile.MaxHours, cfg.Colors)
					return
				}
				log.Fatalf("Login failed: %v", err)
			}
			// Update token in config (in memory for now, save later)
			profile.Token = client.Token
			cfg.Profiles[profileName] = profile
			if err := bakalari.SaveToken(configPath, profileName, client.Token); err != nil {
				log.Printf("Warning: failed to save token: %v", err)
			}

			timetable, err = client.FetchTimetable()
			if err != nil {
				if cached, cacheErr := client.LoadCachedTimetable(); cacheErr == nil {
					log.Printf("Warning: using cached timetable: %v", err)
					timetable = cached
				} else {
					log.Fatalf("Failed to fetch timetable: %v", err)
				}
			}
		}

		bakalari.RenderTimetable(timetable, profile.MaxHours, cfg.Colors)
	},
}

func init() {
	rootCmd.AddCommand(rozvrhCmd)
}
