package bakalari

import "fmt"

// FetchResult describes the outcome of FetchWithLoginFallback.
type FetchResult[T any] struct {
	Data      *T
	FromCache bool // Data was loaded from local disk cache, not the API.
	LoggedIn  bool // A fresh login happened and Client.Token was updated.
}

// FetchWithLoginFallback runs fetchFn. If it fails (e.g. an expired token),
// it logs in once with the given credentials and retries. If the API is
// unreachable even after login, it falls back to whatever loadCacheFn last
// stored on disk. It only returns an error when neither a live fetch nor a
// cached copy is available.
//
// This captures the "try -> login -> retry -> fall back to cache" flow that
// every data command (rozvrh, ukoly, znamky, absence, info) previously
// duplicated by hand.
func FetchWithLoginFallback[T any](c *Client, user, pass string, fetchFn func() (*T, error), loadCacheFn func() (*T, error)) (*FetchResult[T], error) {
	if data, err := fetchFn(); err == nil {
		return &FetchResult[T]{Data: data}, nil
	}

	if loginErr := c.Login(user, pass); loginErr != nil {
		if cached, cacheErr := loadCacheFn(); cacheErr == nil {
			return &FetchResult[T]{Data: cached, FromCache: true}, nil
		}
		return nil, fmt.Errorf("login failed: %w", loginErr)
	}

	if data, err := fetchFn(); err == nil {
		return &FetchResult[T]{Data: data, LoggedIn: true}, nil
	} else if cached, cacheErr := loadCacheFn(); cacheErr == nil {
		return &FetchResult[T]{Data: cached, FromCache: true, LoggedIn: true}, nil
	} else {
		return nil, fmt.Errorf("fetch failed after re-login: %w", err)
	}
}
