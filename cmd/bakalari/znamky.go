package main

import (
	"log"
	"os"
	"path/filepath"

	"github.com/phatevalleyman/bakalari-cli/internal/bakalari"
	"github.com/spf13/cobra"
)

var znamkyCmd = &cobra.Command{
	Use:   "znamky",
	Short: "Show marks",
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

		marks, err := client.FetchMarks()
		if err != nil {
			err = client.Login(profile.User, profile.Pass)
			if err != nil {
				log.Fatalf("Login failed: %v", err)
			}
			profile.Token = client.Token
			cfg.Profiles[profileName] = profile

			marks, err = client.FetchMarks()
			if err != nil {
				log.Fatalf("Failed to fetch marks: %v", err)
			}
		}

		bakalari.RenderMarks(marks)
	},
}

func init() {
	rootCmd.AddCommand(znamkyCmd)
}
