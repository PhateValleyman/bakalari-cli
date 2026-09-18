package main

import (
	"fmt"

	"github.com/spf13/cobra"
)

var ukolyCmd = &cobra.Command{
	Use:   "ukoly",
	Short: "Show homeworks",
	Run: func(cmd *cobra.Command, args []string) {
		fmt.Println("ukoly command executed")
		// Implementation will follow
	},
}

func init() {
	rootCmd.AddCommand(ukolyCmd)
}
