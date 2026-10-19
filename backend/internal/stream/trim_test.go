package stream

import "testing"

func TestLessID(t *testing.T) {
	cases := []struct {
		a, b string
		want bool
	}{
		{"1-0", "2-0", true},
		{"2-0", "1-0", false},
		{"5-1", "5-2", true},
		{"5-2", "5-2", false},
		{"9-0", "10-0", true}, // numeric, not lexical
	}
	for _, c := range cases {
		if got := lessID(c.a, c.b); got != c.want {
			t.Errorf("lessID(%s, %s) = %v, want %v", c.a, c.b, got, c.want)
		}
	}
}
