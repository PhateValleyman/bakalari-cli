package main

import (
	"fmt"
	"log"

	"github.com/phatevalleyman/bakalari-cli/internal/bakalari"
	"github.com/spf13/cobra"
)

var ukolyCmd = &cobra.Command{
	Use:   "ukoly",
	Short: "Show homeworks",
	Run: func(cmd *cobra.Command, args []string) {
		client, cfg, configPath, profileName, profile := setupClient()

		result, err := bakalari.FetchWithLoginFallback(client, profile.User, profile.Pass,
			client.FetchHomeworks, client.LoadCachedHomeworks)
		if err != nil {
			log.Fatalf("Failed to fetch homeworks: %v", err)
		}
		if result.FromCache {
			log.Println("Warning: using cached homeworks")
		}
		persistTokenIfLoggedIn(result.LoggedIn, client, cfg, configPath, profileName, &profile)

		bakalari.RenderHomeworks(result.Data)
		notifyUnfinishedHomeworks(result.Data)
	},
}

// notifyUnfinishedHomeworks sends an Android notification listing unfinished
// homeworks, if any.
func notifyUnfinishedHomeworks(homeworks *bakalari.HomeworksResponse) {
	var unfinished []string
	for _, hw := range homeworks.Homeworks {
		if hw.IsDone {
			continue
		}
		date := hw.DateEnd
		if len(date) > 10 {
			date = date[:10]
		}
		unfinished = append(unfinished, fmt.Sprintf("[%s] %s (do: %s)", hw.Subject.Abbrev, hw.Content, date))
	}

	if len(unfinished) == 0 {
		return
	}
	msg := unfinished[0]
	if len(unfinished) > 1 {
		msg = fmt.Sprintf("%s a %d další", msg, len(unfinished)-1)
	}
	_ = bakalari.NotifyAndroid("bakalari_hw_alert", fmt.Sprintf("Bakaláři: Nesplněný úkol (%d)", len(unfinished)), msg)
}
