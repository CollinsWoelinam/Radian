// Package geo has small spherical-earth helpers. Good to ~0.5% for the
// distances a vehicle covers between fixes; use PostGIS geography for anything
// that needs to be exact.
package geo

import "math"

const earthRadiusM = 6_371_008.8

func rad(d float64) float64 { return d * math.Pi / 180 }
func deg(r float64) float64 { return r * 180 / math.Pi }

// DistanceM is the haversine distance in meters.
func DistanceM(lat1, lon1, lat2, lon2 float64) float64 {
	dLat := rad(lat2 - lat1)
	dLon := rad(lon2 - lon1)
	a := math.Sin(dLat/2)*math.Sin(dLat/2) +
		math.Cos(rad(lat1))*math.Cos(rad(lat2))*math.Sin(dLon/2)*math.Sin(dLon/2)
	return 2 * earthRadiusM * math.Asin(math.Min(1, math.Sqrt(a)))
}

// BearingDeg is the initial bearing from point 1 to point 2, in [0, 360).
func BearingDeg(lat1, lon1, lat2, lon2 float64) float64 {
	y := math.Sin(rad(lon2-lon1)) * math.Cos(rad(lat2))
	x := math.Cos(rad(lat1))*math.Sin(rad(lat2)) -
		math.Sin(rad(lat1))*math.Cos(rad(lat2))*math.Cos(rad(lon2-lon1))
	return math.Mod(deg(math.Atan2(y, x))+360, 360)
}

// Destination moves distanceM meters from (lat, lon) along bearingDeg.
func Destination(lat, lon, bearingDeg, distanceM float64) (float64, float64) {
	δ := distanceM / earthRadiusM
	θ := rad(bearingDeg)
	φ1, λ1 := rad(lat), rad(lon)
	φ2 := math.Asin(math.Sin(φ1)*math.Cos(δ) + math.Cos(φ1)*math.Sin(δ)*math.Cos(θ))
	λ2 := λ1 + math.Atan2(math.Sin(θ)*math.Sin(δ)*math.Cos(φ1), math.Cos(δ)-math.Sin(φ1)*math.Sin(φ2))
	return deg(φ2), math.Mod(deg(λ2)+540, 360) - 180
}
