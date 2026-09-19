package bakalari

import (
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestFetchWithLoginFallbackFreshSuccess(t *testing.T) {
	c := &Client{}
	calls := 0
	fetch := func() (*string, error) {
		calls++
		v := "fresh"
		return &v, nil
	}
	loadCache := func() (*string, error) { return nil, errors.New("should not be called") }

	res, err := FetchWithLoginFallback(c, "user", "pass", fetch, loadCache)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if res.FromCache || res.LoggedIn {
		t.Fatalf("expected fresh non-cached result, got %+v", res)
	}
	if *res.Data != "fresh" {
		t.Fatalf("data = %q, want fresh", *res.Data)
	}
	if calls != 1 {
		t.Fatalf("fetch called %d times, want 1", calls)
	}
}

func TestFetchWithLoginFallbackLoginThenSuccess(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"access_token":"fake-token"}`))
	}))
	defer srv.Close()

	c := NewClient(srv.URL)
	fetchCalls := 0
	fetch := func() (*string, error) {
		fetchCalls++
		if fetchCalls == 1 {
			return nil, errors.New("token expired")
		}
		v := "after-login"
		return &v, nil
	}
	loadCache := func() (*string, error) { return nil, errors.New("no cache") }

	res, err := FetchWithLoginFallback(c, "user", "pass", fetch, loadCache)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !res.LoggedIn || res.FromCache {
		t.Fatalf("expected LoggedIn result, got %+v", res)
	}
	if *res.Data != "after-login" {
		t.Fatalf("data = %q, want after-login", *res.Data)
	}
}

func TestFetchWithLoginFallbackFallsBackToCacheWhenLoginFails(t *testing.T) {
	// An address nothing listens on, so Login() fails with a real network
	// error instead of us having to fake the HTTP layer.
	c := NewClient("http://127.0.0.1:1")
	fetch := func() (*string, error) { return nil, errors.New("network down") }
	loadCache := func() (*string, error) {
		v := "cached"
		return &v, nil
	}

	// Login itself will fail because there is no HTTPClient/BaseURL configured.
	res, err := FetchWithLoginFallback(c, "user", "pass", fetch, loadCache)
	if err != nil {
		t.Fatalf("expected cache fallback instead of error, got: %v", err)
	}
	if !res.FromCache {
		t.Fatalf("expected FromCache result, got %+v", res)
	}
	if *res.Data != "cached" {
		t.Fatalf("data = %q, want cached", *res.Data)
	}
}

func TestFetchWithLoginFallbackReturnsErrorWhenNothingWorks(t *testing.T) {
	c := NewClient("http://127.0.0.1:1")
	fetch := func() (*string, error) { return nil, errors.New("network down") }
	loadCache := func() (*string, error) { return nil, errors.New("no cache") }

	_, err := FetchWithLoginFallback(c, "user", "pass", fetch, loadCache)
	if err == nil {
		t.Fatal("expected error when fetch, login, and cache all fail")
	}
}
