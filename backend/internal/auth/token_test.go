package auth

import (
	"strings"
	"testing"
	"time"
)

func TestAudienceSeparation(t *testing.T) {
	tok, err := New(strings.Repeat("s", 32))
	if err != nil {
		t.Fatal(err)
	}
	device, _ := tok.IssueDevice("vehicle-1", time.Hour)
	dispatcher, _ := tok.Issue(AudienceDispatcher, "dispatcher-1", time.Hour)

	if sub, err := tok.VerifyDevice(device); err != nil || sub != "vehicle-1" {
		t.Fatalf("device token: sub=%q err=%v", sub, err)
	}
	if _, err := tok.VerifyDevice(dispatcher); err == nil {
		t.Error("dispatcher token accepted as a device token")
	}
	if _, err := tok.Verify(AudienceDispatcher, device); err == nil {
		t.Error("device token accepted as a dispatcher token")
	}
	expired, _ := tok.IssueDevice("vehicle-1", -time.Minute)
	if _, err := tok.VerifyDevice(expired); err == nil {
		t.Error("expired token accepted")
	}
	other, _ := New(strings.Repeat("x", 32))
	forged, _ := other.IssueDevice("vehicle-1", time.Hour)
	if _, err := tok.VerifyDevice(forged); err == nil {
		t.Error("token signed with another secret accepted")
	}
}
