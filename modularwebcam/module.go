package modularwebcam

import (
	"context"
	"fmt"
	"runtime"
	"strings"

	"github.com/pion/mediadevices/pkg/driver"
	mdcam "github.com/pion/mediadevices/pkg/driver/camera"
	"go.viam.com/rdk/components/camera"
	"go.viam.com/rdk/components/camera/videosource"
	"go.viam.com/rdk/logging"
	"go.viam.com/rdk/resource"
)

var (
	// Webcam is the modular webcam camera model
	Webcam = resource.NewModel("viam-labs", "modular-webcam", "webcam")
)

// Config wraps RDK's WebcamConfig with an optional DeviceID. When DeviceID is
// set, the constructor resolves it to a video_path via pion/mediadevices'
// driver registry; otherwise the embedded video_path is used directly.
type Config struct {
	videosource.WebcamConfig
	DeviceID string `json:"device_id,omitempty"`
}

func init() {
	resource.RegisterComponent(camera.API, Webcam,
		resource.Registration[camera.Camera, *Config]{
			Constructor: newWebcam,
		},
	)
}

func newWebcam(
	ctx context.Context,
	deps resource.Dependencies,
	conf resource.Config,
	logger logging.Logger,
) (camera.Camera, error) {
	nativeConf, err := resource.NativeConfig[*Config](conf)
	if err != nil {
		return nil, err
	}

	webcamConf := nativeConf.WebcamConfig
	if nativeConf.DeviceID != "" {
		path, err := resolveDeviceID(nativeConf.DeviceID)
		if err != nil {
			return nil, err
		}
		logger.Infow("resolved device_id to video_path",
			"device_id", nativeConf.DeviceID,
			"video_path", path)
		webcamConf.Path = path
	} else {
		logger.Infow("using video_path from config", "video_path", webcamConf.Path)
	}

	delegated := conf
	delegated.ConvertedAttributes = &webcamConf
	return videosource.NewWebcam(ctx, deps, delegated, logger)
}

// resolveDeviceID looks up the pion/mediadevices driver whose label's first
// segment matches deviceID and returns the corresponding video_path. This
// mirrors find-webcams in reverse: find-webcams emits device_id = labelParts[0]
// and video_path = labelParts[1] (Linux) or labelParts[0] (mac/Windows).
func resolveDeviceID(deviceID string) (string, error) {
	if runtime.GOOS == "linux" || runtime.GOOS == "windows" {
		mdcam.Initialize()
	}
	return matchDeviceID(deviceID, driver.GetManager().Query(driver.FilterVideoRecorder()))
}

func matchDeviceID(deviceID string, drivers []driver.Driver) (string, error) {
	for _, d := range drivers {
		parts := strings.Split(d.Info().Label, mdcam.LabelSeparator)
		if parts[0] != deviceID {
			continue
		}
		if len(parts) > 1 {
			return parts[1], nil
		}
		return parts[0], nil
	}
	return "", fmt.Errorf("no camera found matching device_id %q", deviceID)
}
