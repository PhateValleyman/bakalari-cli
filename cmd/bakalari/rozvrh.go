package main

import (
	"log"

	"github.com/phatevalleyman/bakalari-cli/internal/bakalari"
	"github.com/spf13/cobra"
)

var rozvrhCmd = &cobra.Command{
	Use:   "rozvrh",
	Short: "Show timetable",
	Run: func(cmd *cobra.Command, args []string) {
		client, cfg, configPath, profileName, profile := setupClient()

		result, err := bakalari.FetchWithLoginFallback(client, profile.User, profile.Pass,
			client.FetchTimetable, client.LoadCachedTimetable)
		if err != nil {
			log.Fatalf("Failed to fetch timetable: %v", err)
		}
		if result.FromCache {
			log.Println("Warning: using cached timetable")
		}
		persistTokenIfLoggedIn(result.LoggedIn, client, cfg, configPath, profileName, &profile)

		bakalari.RenderTimetable(result.Data, profile.MaxHours, cfg.Colors)
	},
}

func init() {
	rootCmd.AddCommand(rozvrhCmd)
}
