package main

import (
	"fmt"
	"log"
	"os"
	"path/filepath"

	"github.com/phatevalleyman/bakalari-cli/internal/bakalari"
	"github.com/spf13/cobra"
)

var (
	cacheList  bool
	cachePath  bool
	cacheClear bool
)

var cacheCmd = &cobra.Command{
	Use:   "cache",
	Short: "Manage local cache",
	Run: func(cmd *cobra.Command, args []string) {
		configPath := configFile
		if configPath == "" {
			configPath = os.Getenv("BAKALARI_CONFIG")
		}

		cfg, err := bakalari.LoadConfig(configPath)
		if err != nil {
			log.Fatalf("Failed to load config: %v", err)
		}

		cacheDir := cfg.General.CacheDir
		if cacheDir == "" {
			home, _ := os.UserHomeDir()
			cacheDir = filepath.Join(home, ".cache", "bakalari-cli")
		}

		if cachePath {
			fmt.Println(cacheDir)
			return
		}

		if cacheClear {
			if err := bakalari.ClearCache(cacheDir); err != nil {
				log.Fatalf("Failed to clear cache: %v", err)
			}
			return
		}

		// Default is list
		if err := bakalari.ListCache(cacheDir); err != nil {
			log.Fatalf("Failed to list cache: %v", err)
		}
	},
}

func init() {
	cacheCmd.Flags().BoolVar(&cacheList, "list", false, "List cache files")
	cacheCmd.Flags().BoolVar(&cachePath, "path", false, "Show cache path")
	cacheCmd.Flags().BoolVar(&cacheClear, "clear", false, "Clear cache")
	rootCmd.AddCommand(cacheCmd)
}
