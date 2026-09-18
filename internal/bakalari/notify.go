package bakalari

import (
	"os/exec"
)

// NotifyAndroid sends a notification via termux-notification if available.
func NotifyAndroid(id, title, content string) error {
	_, err := exec.LookPath("termux-notification")
	if err != nil {
		return nil // Not in Termux or tool missing
	}

	cmd := exec.Command("termux-notification",
		"--id", id,
		"--title", title,
		"--content", content,
		"--priority", "high",
		"--sound",
		"--vibrate", "500,200,500",
	)
	return cmd.Run()
}
