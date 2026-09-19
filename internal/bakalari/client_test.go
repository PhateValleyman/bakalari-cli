package bakalari

import "testing"

func TestClientCacheFileStripsSchemeAndColon(t *testing.T) {
	c := NewClient("https://zssumava.bakalari.cz")
	c.Profile = "Dzonny"
	c.CacheDir = t.TempDir()

	got := c.cacheFile("absence")
	want := c.CacheDir + "/absence-Dzonny-zssumava.bakalari.cz.json"
	if got != want {
		t.Fatalf("cacheFile() = %q, want %q", got, want)
	}
}
