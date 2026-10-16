// Package osrm is a small client for an OSRM routing server: drive-time
// matrices for dispatch and road geometry for maps.
package osrm

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"
)

type Point struct{ Lat, Lon float64 }

type Client struct {
	base string
	http *http.Client
}

func New(baseURL string) *Client {
	return &Client{base: strings.TrimRight(baseURL, "/"), http: &http.Client{Timeout: 5 * time.Second}}
}

// TableResult holds drive time and distance from each source to the destination.
// An entry is negative when OSRM found no route.
type TableResult struct {
	DurationsS []float64
	DistancesM []float64
}

// Table returns drive times and distances from every source to one destination.
func (c *Client) Table(ctx context.Context, sources []Point, dest Point) (TableResult, error) {
	if len(sources) == 0 {
		return TableResult{}, nil
	}
	coords := append(append([]Point{}, sources...), dest)
	srcIdx := make([]string, len(sources))
	for i := range sources {
		srcIdx[i] = strconv.Itoa(i)
	}
	url := fmt.Sprintf("%s/table/v1/driving/%s?sources=%s&destinations=%d&annotations=duration,distance",
		c.base, encode(coords), strings.Join(srcIdx, ";"), len(sources))

	var body struct {
		Code      string       `json:"code"`
		Message   string       `json:"message"`
		Durations [][]*float64 `json:"durations"`
		Distances [][]*float64 `json:"distances"`
	}
	if err := c.get(ctx, url, &body); err != nil {
		return TableResult{}, err
	}
	if body.Code != "Ok" {
		return TableResult{}, fmt.Errorf("osrm table: %s %s", body.Code, body.Message)
	}
	res := TableResult{DurationsS: make([]float64, len(sources)), DistancesM: make([]float64, len(sources))}
	for i := range sources {
		res.DurationsS[i], res.DistancesM[i] = -1, -1
		if i < len(body.Durations) && len(body.Durations[i]) > 0 && body.Durations[i][0] != nil {
			res.DurationsS[i] = *body.Durations[i][0]
		}
		if i < len(body.Distances) && len(body.Distances[i]) > 0 && body.Distances[i][0] != nil {
			res.DistancesM[i] = *body.Distances[i][0]
		}
	}
	return res, nil
}

type Route struct {
	DurationS float64
	DistanceM float64
	// [lon, lat] pairs, ready for GeoJSON / deck.gl.
	Coordinates [][2]float64
}

// Route returns the fastest driving route through the given points in order.
func (c *Client) Route(ctx context.Context, pts ...Point) (Route, error) {
	if len(pts) < 2 {
		return Route{}, errors.New("osrm route: need at least two points")
	}
	url := fmt.Sprintf("%s/route/v1/driving/%s?overview=full&geometries=geojson", c.base, encode(pts))
	var body struct {
		Code    string `json:"code"`
		Message string `json:"message"`
		Routes  []struct {
			Duration float64 `json:"duration"`
			Distance float64 `json:"distance"`
			Geometry struct {
				Coordinates [][2]float64 `json:"coordinates"`
			} `json:"geometry"`
		} `json:"routes"`
	}
	if err := c.get(ctx, url, &body); err != nil {
		return Route{}, err
	}
	if body.Code != "Ok" || len(body.Routes) == 0 {
		return Route{}, fmt.Errorf("osrm route: %s %s", body.Code, body.Message)
	}
	r := body.Routes[0]
	return Route{DurationS: r.Duration, DistanceM: r.Distance, Coordinates: r.Geometry.Coordinates}, nil
}

func (c *Client) get(ctx context.Context, url string, out any) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return err
	}
	res, err := c.http.Do(req)
	if err != nil {
		return fmt.Errorf("osrm: %w", err)
	}
	defer res.Body.Close()
	// OSRM reports errors (e.g. NoRoute) as JSON with a 400, so decode either way.
	return json.NewDecoder(res.Body).Decode(out)
}

func encode(pts []Point) string {
	parts := make([]string, len(pts))
	for i, p := range pts {
		parts[i] = strconv.FormatFloat(p.Lon, 'f', 6, 64) + "," + strconv.FormatFloat(p.Lat, 'f', 6, 64)
	}
	return strings.Join(parts, ";")
}
