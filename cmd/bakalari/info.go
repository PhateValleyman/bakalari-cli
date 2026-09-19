package main

import (
	"log"

	"github.com/phatevalleyman/bakalari-cli/internal/bakalari"
	"github.com/spf13/cobra"
)

var infoCmd = &cobra.Command{
	Use:   "info",
	Short: "Show student info",
	Run: func(cmd *cobra.Command, args []string) {
		client, cfg, configPath, profileName, profile := setupClient()

		result, err := bakalari.FetchWithLoginFallback(client, profile.User, profile.Pass,
			client.FetchUserInfo, client.LoadCachedUserInfo)
		if err != nil {
			log.Fatalf("Failed to fetch user info: %v", err)
		}
		if result.FromCache {
			log.Println("Warning: using cached user info")
		}
		persistTokenIfLoggedIn(result.LoggedIn, client, cfg, configPath, profileName, &profile)

		// Absence and marks are supplementary here: if they're unavailable
		// (offline, or this account can't see them), info still renders
		// with whatever we have, falling back to cache and finally to nil.
		absence, err := client.FetchAbsence()
		if err != nil {
			absence, _ = client.LoadCachedAbsence()
		}

		marks, err := client.FetchMarks()
		if err != nil {
			marks, _ = client.LoadCachedMarks()
		}

		bakalari.RenderInfo(result.Data, absence, marks)
	},
}

func init() {
	rootCmd.AddCommand(infoCmd)
}
