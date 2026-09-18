package bakalari

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// Client handles communication with the Bakalari API.
type Client struct {
	BaseURL    string
	HTTPClient *http.Client
	Token      string
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
	return &result, err
}

// FetchHomeworks retrieves the homework assignments.
func (c *Client) FetchHomeworks() (*HomeworksResponse, error) {
	var result HomeworksResponse
	err := c.get("/api/3/homeworks", &result)
	return &result, err
}

// FetchMarks retrieves the student's grades.
func (c *Client) FetchMarks() (*MarksResponse, error) {
	var result MarksResponse
	err := c.get("/api/3/marks", &result)
	return &result, err
}

// FetchAbsence retrieves the student's absence.
func (c *Client) FetchAbsence() (*AbsenceResponse, error) {
	var result AbsenceResponse
	err := c.get("/api/3/absence/student", &result)
	return &result, err
}

// FetchUserInfo retrieves the student's profile info.
func (c *Client) FetchUserInfo() (*UserInfo, error) {
	var result UserInfo
	err := c.get("/api/3/user", &result)
	return &result, err
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
