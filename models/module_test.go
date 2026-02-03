package models

import (
	"testing"

	"go.viam.com/test"
)

func TestWebcamRegistration(t *testing.T) {
	// Verify model is registered correctly
	test.That(t, Webcam.Name, test.ShouldEqual, "webcam")
	test.That(t, string(Webcam.Family.Namespace), test.ShouldEqual, "viam-labs")
	test.That(t, Webcam.Family.Name, test.ShouldEqual, "modular-webcam")
}
