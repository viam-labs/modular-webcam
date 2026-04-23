package modularwebcam

import (
	"testing"

	"github.com/pion/mediadevices/pkg/driver"
	"github.com/pion/mediadevices/pkg/prop"
	"go.viam.com/test"
)

func TestWebcamRegistration(t *testing.T) {
	// Verify model is registered correctly
	test.That(t, Webcam.Name, test.ShouldEqual, "webcam")
	test.That(t, string(Webcam.Family.Namespace), test.ShouldEqual, "viam-labs")
	test.That(t, Webcam.Family.Name, test.ShouldEqual, "modular-webcam")
}

// fakeDriver is a minimal driver.Driver used to exercise matchDeviceID without
// touching the global mediadevices driver registry.
type fakeDriver struct{ label string }

func (f fakeDriver) Open() error               { return nil }
func (f fakeDriver) Close() error              { return nil }
func (f fakeDriver) Properties() []prop.Media  { return nil }
func (f fakeDriver) ID() string                { return f.label }
func (f fakeDriver) Info() driver.Info         { return driver.Info{Label: f.label} }
func (f fakeDriver) Status() driver.State      { return driver.StateClosed }

func TestMatchDeviceID(t *testing.T) {
	drivers := []driver.Driver{
		fakeDriver{label: "video0;video0"},        // Linux: device_id == video_path
		fakeDriver{label: "deviceA;/dev/video2"},  // Linux: device_id distinct from path
		fakeDriver{label: "0x8020000005ac8514"},   // mac/Windows: no separator
	}

	for _, tc := range []struct {
		name     string
		deviceID string
		want     string
		wantErr  bool
	}{
		{"linux same id and path", "video0", "video0", false},
		{"linux distinct id and path", "deviceA", "/dev/video2", false},
		{"mac no separator", "0x8020000005ac8514", "0x8020000005ac8514", false},
		{"no match", "missing", "", true},
		{"empty drivers errors", "video0", "", true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			input := drivers
			if tc.name == "empty drivers errors" {
				input = nil
			}
			got, err := matchDeviceID(tc.deviceID, input)
			if tc.wantErr {
				test.That(t, err, test.ShouldNotBeNil)
				return
			}
			test.That(t, err, test.ShouldBeNil)
			test.That(t, got, test.ShouldEqual, tc.want)
		})
	}
}
