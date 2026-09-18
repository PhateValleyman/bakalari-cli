package main

import (
	"fmt"

	"github.com/spf13/cobra"
)

var rozvrhCmd = &cobra.Command{
	Use:   "rozvrh",
	Short: "Show timetable",
	Run: func(cmd *cobra.Command, args []string) {
		fmt.Println("rozvrh command executed")
		// Implementation will follow
	},
}

func init() {
	rootCmd.AddCommand(rozvrhCmd)
}
