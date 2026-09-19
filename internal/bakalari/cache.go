package bakalari

import (
	"fmt"
	"github.com/fatih/color"
	"os"
	"path/filepath"
	"sort"
)

// ListCache lists all files in the cache directory.
func ListCache(cacheDir string) error {
	if _, err := os.Stat(cacheDir); os.IsNotExist(err) {
		fmt.Println("(cache zatím neexistuje)")
		return nil
	}

	files, err := os.ReadDir(cacheDir)
	if err != nil {
		return err
	}

	var fileList []string
	for _, f := range files {
		if !f.IsDir() {
			info, _ := f.Info()
			fileList = append(fileList, fmt.Sprintf("%-40s %8d B", f.Name(), info.Size()))
		}
	}

	sort.Strings(fileList)
	for _, s := range fileList {
		fmt.Println(s)
	}

	return nil
}

// ClearCache deletes all files in the cache directory.
func ClearCache(cacheDir string) error {
	if _, err := os.Stat(cacheDir); os.IsNotExist(err) {
		return nil
	}

	files, err := os.ReadDir(cacheDir)
	if err != nil {
		return err
	}

	for _, f := range files {
		if !f.IsDir() {
			os.Remove(filepath.Join(cacheDir, f.Name()))
		}
	}

	fmt.Printf("%sCache vyčištěna: %s%s\n", color.New(color.FgGreen).SprintFunc()("OK:    "), cacheDir, "")
	return nil
}
