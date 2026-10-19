package stream

import (
	"context"
	"strconv"
	"strings"

	"github.com/redis/go-redis/v9"
)

// TrimConsumed drops telemetry entries every consumer group is done with:
// everything older than the oldest entry still pending in, or not yet
// delivered to, any group. Broadcast tails the stream without a group and
// only needs new entries.
func TrimConsumed(ctx context.Context, rdb *redis.Client) error {
	groups, err := rdb.XInfoGroups(ctx, Telemetry).Result()
	if err != nil || len(groups) == 0 {
		return err
	}
	minID := ""
	for _, g := range groups {
		id := g.LastDeliveredID
		if g.Pending > 0 {
			sum, err := rdb.XPending(ctx, Telemetry, g.Name).Result()
			if err != nil {
				return err
			}
			id = sum.Lower
		}
		if minID == "" || lessID(id, minID) {
			minID = id
		}
	}
	if minID == "" || minID == "0-0" {
		return nil
	}
	return rdb.XTrimMinIDApprox(ctx, Telemetry, minID, 0).Err()
}

// lessID compares Redis stream IDs ("<ms>-<seq>").
func lessID(a, b string) bool {
	am, as := splitID(a)
	bm, bs := splitID(b)
	return am < bm || (am == bm && as < bs)
}

func splitID(id string) (uint64, uint64) {
	ms, seq, _ := strings.Cut(id, "-")
	m, _ := strconv.ParseUint(ms, 10, 64)
	s, _ := strconv.ParseUint(seq, 10, 64)
	return m, s
}
