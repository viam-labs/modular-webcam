package modularwebcam

import (
	"go.viam.com/rdk/components/camera"
	"go.viam.com/rdk/components/camera/videosource"
	"go.viam.com/rdk/resource"
)

var (
	// Webcam is the modular webcam camera model
	Webcam = resource.NewModel("viam-labs", "modular-webcam", "webcam")
)

func init() {
	// Register using RDK's existing webcam implementation
	resource.RegisterComponent(camera.API, Webcam,
		resource.Registration[camera.Camera, *videosource.WebcamConfig]{
			Constructor: videosource.NewWebcam,
		},
	)
}
