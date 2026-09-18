package main

import (
	"fmt"
	"log"
	"os"
	"path/filepath"

	"github.com/phatevalleyman/bakalari-cli/internal/bakalari"
	"github.com/spf13/cobra"
)

var ukolyCmd = &cobra.Command{
	Use:   "ukoly",
	Short: "Show homeworks",
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

		homeworks, err := client.FetchHomeworks()
		if err != nil {
			err = client.Login(profile.User, profile.Pass)
			if err != nil {
				log.Fatalf("Login failed: %v", err)
			}
			profile.Token = client.Token
			cfg.Profiles[profileName] = profile
			if err := bakalari.SaveToken(configPath, profileName, client.Token); err != nil {
				log.Printf("Warning: failed to save token: %v", err)
			}

			homeworks, err = client.FetchHomeworks()
			if err != nil {
				log.Fatalf("Failed to fetch homeworks: %v", err)
			}
		}

		bakalari.RenderHomeworks(homeworks)

		// Check for unfinished homeworks and notify
		var unfinished []string
		for _, hw := range homeworks.Homeworks {
			if !hw.IsDone {
				msg := fmt.Sprintf("[%s] %s (do: %s)", hw.Subject.Abbrev, hw.Content, hw.DateEnd[:10])
				unfinished = append(unfinished, msg)
			}
		}

		if len(unfinished) > 0 {
			msg := unfinished[0]
			if len(unfinished) > 1 {
				msg = fmt.Sprintf("%s and %d more", msg, len(unfinished)-1)
			}
			bakalari.NotifyAndroid("bakalari_hw_alert", fmt.Sprintf("Bakaláři: Nesplněný úkol (%d)", len(unfinished)), msg)
		}
	},
}

func init() {
	rootCmd.AddCommand(ukolyCmd)
}
