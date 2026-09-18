package main

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"
)

var (
	userProfile string
	configFile  string
)

var rootCmd = &cobra.Command{
	Use:     "bakalari",
	Short:   "Bakalari CLI - Access Bakalari school system from terminal",
	Version: "0.5.0",
	Long: `A command line interface for the Bakalari school system API.
Supports timetable, homeworks, marks, absence and more.`,
}

func Execute() {
	if err := rootCmd.Execute(); err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
}

func init() {
	rootCmd.PersistentFlags().StringVar(&userProfile, "user", "", "User profile to use")
	rootCmd.PersistentFlags().StringVar(&configFile, "config", "", "Config file (default is $HOME/.config/bakalari-cli/config.toml)")
}
