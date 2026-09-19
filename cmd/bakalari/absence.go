package main

import (
	"log"

	"github.com/phatevalleyman/bakalari-cli/internal/bakalari"
	"github.com/spf13/cobra"
)

var absenceCmd = &cobra.Command{
	Use:   "absence",
	Short: "Show absence",
	Run: func(cmd *cobra.Command, args []string) {
		client, cfg, configPath, profileName, profile := setupClient()

		result, err := bakalari.FetchWithLoginFallback(client, profile.User, profile.Pass,
			client.FetchAbsence, client.LoadCachedAbsence)
		if err != nil {
			log.Fatalf("Failed to fetch absence: %v", err)
		}
		if result.FromCache {
			log.Println("Warning: using cached absence")
		}
		persistTokenIfLoggedIn(result.LoggedIn, client, cfg, configPath, profileName, &profile)

		bakalari.RenderAbsence(result.Data)
	},
}

func init() {
	rootCmd.AddCommand(absenceCmd)
}
