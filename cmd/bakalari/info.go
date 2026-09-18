package main

import (
	"log"
	"os"

	"github.com/phatevalleyman/bakalari-cli/internal/bakalari"
	"github.com/spf13/cobra"
)

var infoCmd = &cobra.Command{
	Use:   "info",
	Short: "Show student info",
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

		userInfo, err := client.FetchUserInfo()
		if err != nil {
			err = client.Login(profile.User, profile.Pass)
			if err != nil {
				log.Fatalf("Login failed: %v", err)
			}
			profile.Token = client.Token
			cfg.Profiles[profileName] = profile

			userInfo, err = client.FetchUserInfo()
			if err != nil {
				log.Fatalf("Failed to fetch user info: %v", err)
			}
		}

		absence, _ := client.FetchAbsence()
		marks, _ := client.FetchMarks()

		bakalari.RenderInfo(userInfo, absence, marks)
	},
}

func init() {
	rootCmd.AddCommand(infoCmd)
}
