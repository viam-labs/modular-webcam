package main

import (
	"os"
	"runtime"

	"github.com/viam-labs/modular-webcam/modularwebcam"

	mdcam "github.com/pion/mediadevices/pkg/driver/camera"
	"go.viam.com/rdk/components/camera"
	"go.viam.com/rdk/logging"
	"go.viam.com/rdk/module"
	"go.viam.com/rdk/resource"
)

var logger = logging.NewDebugLogger("modular-webcam")

func main() {
	if runtime.GOOS == "darwin" {
		if err := mdcam.StartObserver(); err != nil {
			logger.Errorw("failed to start camera observer", "error", err)
			os.Exit(1)
		}
		defer mdcam.DestroyObserver()
	}

	module.ModularMain(
		resource.APIModel{API: camera.API, Model: modularwebcam.Webcam},
	)
}
