package main

import (
	"fmt"
	"log"

	"github.com/phatevalleyman/bakalari-cli/internal/bakalari"
	"github.com/spf13/cobra"
)

var znamkyCmd = &cobra.Command{
	Use:   "znamky",
	Short: "Show marks",
	Run: func(cmd *cobra.Command, args []string) {
		client, cfg, configPath, profileName, profile := setupClient()

		result, err := bakalari.FetchWithLoginFallback(client, profile.User, profile.Pass,
			client.FetchMarks, client.LoadCachedMarks)
		if err != nil {
			log.Fatalf("Failed to fetch marks: %v", err)
		}
		if result.FromCache {
			log.Println("Warning: using cached marks")
		}
		persistTokenIfLoggedIn(result.LoggedIn, client, cfg, configPath, profileName, &profile)

		bakalari.RenderMarks(result.Data)
		notifyNewMarks(result.Data)
	},
}

// notifyNewMarks sends an Android notification when the API reports newly
// added grades (IsNew), mirroring the existing unfinished-homework alert.
func notifyNewMarks(marks *bakalari.MarksResponse) {
	var newest []string
	for _, s := range marks.Subjects {
		for _, m := range s.Marks {
			if !m.IsNew {
				continue
			}
			text := m.MarkText
			if text == "" {
				text = "-"
			}
			newest = append(newest, fmt.Sprintf("[%s] %s: %s", s.Subject.Abbrev, m.Caption, text))
		}
	}

	if len(newest) == 0 {
		return
	}
	msg := newest[0]
	if len(newest) > 1 {
		msg = fmt.Sprintf("%s a %d další", msg, len(newest)-1)
	}
	_ = bakalari.NotifyAndroid("bakalari_marks_alert", fmt.Sprintf("Bakaláři: Nová známka (%d)", len(newest)), msg)
}
