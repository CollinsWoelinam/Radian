package geo

import "math"

// Ring is a closed or open list of [lon, lat] vertices (GeoJSON order).
type Ring [][2]float64

// Polygon is an outer ring followed by any holes.
type Polygon []Ring

// MultiPolygon matches PostGIS MULTIPOLYGON / GeoJSON MultiPolygon.
type MultiPolygon []Polygon

// Contains reports whether the point is inside the area. Uses the even-odd
// rule per polygon, so holes are excluded.
func (m MultiPolygon) Contains(lat, lon float64) bool {
	for _, p := range m {
		in := false
		for _, r := range p {
			if r.crossings(lat, lon)%2 == 1 {
				in = !in
			}
		}
		if in {
			return true
		}
	}
	return false
}

func (r Ring) crossings(lat, lon float64) int {
	n := 0
	for i, j := 0, len(r)-1; i < len(r); j, i = i, i+1 {
		xi, yi := r[i][0], r[i][1]
		xj, yj := r[j][0], r[j][1]
		if (yi > lat) != (yj > lat) && lon < (xj-xi)*(lat-yi)/(yj-yi)+xi {
			n++
		}
	}
	return n
}

// BoundaryDistanceM is the distance in meters from the point to the nearest
// edge. It projects locally (equirectangular), which is accurate to well under
// a meter at city scale; that is all a GPS-accuracy comparison needs.
func (m MultiPolygon) BoundaryDistanceM(lat, lon float64) float64 {
	kx := earthRadiusM * math.Cos(rad(lat)) * math.Pi / 180
	ky := earthRadiusM * math.Pi / 180
	best := math.Inf(1)
	for _, p := range m {
		for _, r := range p {
			for i, j := 0, len(r)-1; i < len(r); j, i = i, i+1 {
				ax, ay := (r[j][0]-lon)*kx, (r[j][1]-lat)*ky
				bx, by := (r[i][0]-lon)*kx, (r[i][1]-lat)*ky
				best = math.Min(best, segmentDistance(ax, ay, bx, by))
			}
		}
	}
	return best
}

// segmentDistance is the distance from the origin to segment AB.
func segmentDistance(ax, ay, bx, by float64) float64 {
	dx, dy := bx-ax, by-ay
	t := 0.0
	if l2 := dx*dx + dy*dy; l2 > 0 {
		t = math.Max(0, math.Min(1, -(ax*dx+ay*dy)/l2))
	}
	return math.Hypot(ax+t*dx, ay+t*dy)
}

// Bounds is the area's bounding box, for a cheap reject before Contains.
func (m MultiPolygon) Bounds() (minLat, minLon, maxLat, maxLon float64) {
	minLat, minLon, maxLat, maxLon = 90, 180, -90, -180
	for _, p := range m {
		for _, r := range p {
			for _, v := range r {
				minLon, maxLon = math.Min(minLon, v[0]), math.Max(maxLon, v[0])
				minLat, maxLat = math.Min(minLat, v[1]), math.Max(maxLat, v[1])
			}
		}
	}
	return
}
