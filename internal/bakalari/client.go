package bakalari

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// Client handles communication with the Bakalari API.
type Client struct {
	BaseURL    string
	HTTPClient *http.Client
	Token      string
	CacheDir   string
	Profile    string // Profile name for cache file naming
}

// NewClient creates a new API client.
func NewClient(schoolHost string) *Client {
	baseURL := schoolHost
	if !strings.HasPrefix(baseURL, "http") {
		baseURL = "https://" + baseURL
	}
	baseURL = strings.TrimSuffix(baseURL, "/")

	return &Client{
		BaseURL: baseURL,
		HTTPClient: &http.Client{
			Timeout: 30 * time.Second,
		},
	}
}

func (c *Client) cacheFile(name string) string {
	if c.CacheDir == "" {
		return ""
	}
	safeName := fmt.Sprintf("%s-%s-%s.json", name, c.Profile, strings.ReplaceAll(c.BaseURL, "/", "_"))
	return filepath.Join(c.CacheDir, safeName)
}

func (c *Client) saveCache(name string, v interface{}) {
	file := c.cacheFile(name)
	if file == "" {
		return
	}
	_ = os.MkdirAll(filepath.Dir(file), 0755)
	data, _ := json.Marshal(v)
	_ = os.WriteFile(file, data, 0600)
}

func (c *Client) loadCache(name string, v interface{}) error {
	file := c.cacheFile(name)
	if file == "" {
		return fmt.Errorf("cache disabled")
	}
	data, err := os.ReadFile(file)
	if err != nil {
		return err
	}
	return json.Unmarshal(data, v)
}

// Login authenticates with the API and stores the access token.
func (c *Client) Login(username, password string) error {
	loginURL := fmt.Sprintf("%s/api/login", c.BaseURL)
	data := url.Values{}
	data.Set("client_id", "ANDR")
	data.Set("grant_type", "password")
	data.Set("username", username)
	data.Set("password", password)

	resp, err := c.HTTPClient.PostForm(loginURL, data)
	if err != nil {
		return fmt.Errorf("login request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("login failed with status: %s", resp.Status)
	}

	var result struct {
		AccessToken string `json:"access_token"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return fmt.Errorf("failed to decode login response: %w", err)
	}

	c.Token = result.AccessToken
	return nil
}

// FetchTimetable retrieves the current timetable.
func (c *Client) FetchTimetable() (*TimetableResponse, error) {
	var result TimetableResponse
	err := c.get("/api/3/timetable/actual", &result)
	if err == nil {
		c.saveCache("timetable", &result)
		return &result, nil
	}
	if c.loadCache("timetable", &result) == nil {
		return &result, nil
	}
	return nil, err
}

// FetchHomeworks retrieves the homework assignments.
func (c *Client) FetchHomeworks() (*HomeworksResponse, error) {
	var result HomeworksResponse
	err := c.get("/api/3/homeworks", &result)
	if err == nil {
		c.saveCache("homeworks", &result)
		return &result, nil
	}
	if c.loadCache("homeworks", &result) == nil {
		return &result, nil
	}
	return nil, err
}

// FetchMarks retrieves the student's grades.
func (c *Client) FetchMarks() (*MarksResponse, error) {
	var result MarksResponse
	err := c.get("/api/3/marks", &result)
	if err == nil {
		c.saveCache("marks", &result)
		return &result, nil
	}
	if c.loadCache("marks", &result) == nil {
		return &result, nil
	}
	return nil, err
}

// FetchAbsence retrieves the student's absence.
func (c *Client) FetchAbsence() (*AbsenceResponse, error) {
	var result AbsenceResponse
	err := c.get("/api/3/absence/student", &result)
	if err == nil {
		c.saveCache("absence", &result)
		return &result, nil
	}
	if c.loadCache("absence", &result) == nil {
		return &result, nil
	}
	return nil, err
}

// FetchUserInfo retrieves the student's profile info.
func (c *Client) FetchUserInfo() (*UserInfo, error) {
	var result UserInfo
	err := c.get("/api/3/user", &result)
	if err == nil {
		c.saveCache("info", &result)
		return &result, nil
	}
	if c.loadCache("info", &result) == nil {
		return &result, nil
	}
	return nil, err
}

func (c *Client) get(path string, v interface{}) error {
	fullURL := c.BaseURL + path
	req, err := http.NewRequest("GET", fullURL, nil)
	if err != nil {
		return err
	}

	if c.Token != "" {
		req.Header.Set("Authorization", "Bearer "+c.Token)
	}

	resp, err := c.HTTPClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("request failed with status %s: %s", resp.Status, string(body))
	}

	return json.NewDecoder(resp.Body).Decode(v)
}
