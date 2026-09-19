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
	}
	return &result, err
}

// FetchHomeworks retrieves the homeworks data.
func (c *Client) FetchHomeworks() (*HomeworksResponse, error) {
	var result HomeworksResponse
	err := c.get("/api/3/homeworks", &result)
	if err == nil {
		c.saveCache("homeworks", &result)
	}
	return &result, err
}

// FetchMarks retrieves the marks data.
func (c *Client) FetchMarks() (*MarksResponse, error) {
	var result MarksResponse
	err := c.get("/api/3/marks", &result)
	if err == nil {
		c.saveCache("marks", &result)
	}
	return &result, err
}

// FetchAbsence retrieves the absence data.
func (c *Client) FetchAbsence() (*AbsenceResponse, error) {
	var result AbsenceResponse
	err := c.get("/api/3/absence/student", &result)
	if err == nil {
		c.saveCache("absence", &result)
	}
	return &result, err
}

// FetchUserInfo retrieves the student's profile info.
func (c *Client) FetchUserInfo() (*UserInfo, error) {
	var result UserInfo
	err := c.get("/api/3/user", &result)
	if err == nil {
		c.saveCache("info", &result)
	}
	return &result, err
}

// LoadCachedTimetable loads the last successfully fetched timetable.
func (c *Client) LoadCachedTimetable() (*TimetableResponse, error) {
	var result TimetableResponse
	if err := c.loadCache("timetable", &result); err != nil {
		return nil, err
	}
	return &result, nil
}

// LoadCachedHomeworks loads the last successfully fetched homeworks.
func (c *Client) LoadCachedHomeworks() (*HomeworksResponse, error) {
	var result HomeworksResponse
	if err := c.loadCache("homeworks", &result); err != nil { return nil, err }
	return &result, nil
}

// LoadCachedMarks loads the last successfully fetched marks.
func (c *Client) LoadCachedMarks() (*MarksResponse, error) {
	var result MarksResponse
	if err := c.loadCache("marks", &result); err != nil { return nil, err }
	return &result, nil
}

// LoadCachedAbsence loads the last successfully fetched absence data.
func (c *Client) LoadCachedAbsence() (*AbsenceResponse, error) {
	var result AbsenceResponse
	if err := c.loadCache("absence", &result); err != nil { return nil, err }
	return &result, nil
}

// LoadCachedUserInfo loads the last successfully fetched user info.
func (c *Client) LoadCachedUserInfo() (*UserInfo, error) {
	var result UserInfo
	if err := c.loadCache("info", &result); err != nil { return nil, err }
	return &result, nil
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
