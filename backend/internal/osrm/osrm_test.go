package osrm

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestTable(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Coordinates are lon,lat; sources first, destination last.
		if !strings.Contains(r.URL.Path, "/table/v1/driving/-0.200000,5.600000;-0.100000,5.700000;-0.150000,5.650000") {
			t.Errorf("unexpected path %s", r.URL.Path)
		}
		// OSRM wants ';'-separated lists, which net/url won't parse; check the raw query.
		for _, want := range []string{"sources=0;1", "destinations=2"} {
			if !strings.Contains(r.URL.RawQuery, want) {
				t.Errorf("query %q missing %q", r.URL.RawQuery, want)
			}
		}
		w.Write([]byte(`{"code":"Ok","durations":[[300.5],[null]],"distances":[[2500],[null]]}`))
	}))
	defer srv.Close()

	res, err := New(srv.URL).Table(context.Background(),
		[]Point{{Lat: 5.6, Lon: -0.2}, {Lat: 5.7, Lon: -0.1}}, Point{Lat: 5.65, Lon: -0.15})
	if err != nil {
		t.Fatal(err)
	}
	if res.DurationsS[0] != 300.5 || res.DistancesM[0] != 2500 {
		t.Errorf("first source = %v / %v", res.DurationsS[0], res.DistancesM[0])
	}
	if res.DurationsS[1] != -1 {
		t.Errorf("unroutable source should be -1, got %v", res.DurationsS[1])
	}
}

func TestRouteNoRoute(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
		w.Write([]byte(`{"code":"NoRoute","message":"Impossible route between points"}`))
	}))
	defer srv.Close()
	_, err := New(srv.URL).Route(context.Background(), Point{5.6, -0.2}, Point{5.7, -0.1})
	if err == nil || !strings.Contains(err.Error(), "NoRoute") {
		t.Fatalf("err = %v, want NoRoute", err)
	}
}
