package edit

import (
	"fmt"
	"io"
	"os"
	"path"
	"path/filepath"
	"time"

	"github.com/spf13/cobra"
	"github.com/warewulf/warewulf/internal/pkg/overlay"
	"github.com/warewulf/warewulf/internal/pkg/util"
	"github.com/warewulf/warewulf/internal/pkg/wwlog"
)

const initialTemplate = `# This is a Warewulf Template file.
#
# This file (suffix '.ww') will be automatically rewritten without the suffix
# when the overlay is rendered for the individual nodes. Here are some examples
# of macros and logic which can be used within this file:
#
# Node FQDN = {{.Id}}
# Node Cluster = {{.ClusterName}}
# Network Config = {{.NetDevs.eth0.Ipaddr}}, {{.NetDevs.eth0.Hwaddr}}, etc.
#
# Go to the documentation pages for more information:
# https://warewulf.org/docs/main/contents/overlays.html
#
# Keep the following for better reference:
# ---
# This file is autogenerated by warewulf
# Host:   {{.BuildHost}}
# Time:   {{.BuildTime}}
# Source: {{.BuildSource}}
`

func CobraRunE(cmd *cobra.Command, args []string) error {
	overlayName := args[0]
	fileName := args[1]

	overlaySourceDir := overlay.OverlaySourceDir(overlayName)
	if !util.IsDir(overlaySourceDir) {
		return fmt.Errorf("overlay does not exist: %s", overlayName)
	}

	overlayFile := path.Join(overlaySourceDir, fileName)
	wwlog.Debug("Will edit overlay file: %s", overlayFile)

	overlayFileDir := path.Dir(overlayFile)
	if CreateDirs {
		err := os.MkdirAll(overlayFileDir, 0755)
		if err != nil {
			return fmt.Errorf("could not create directory: %s", overlayFileDir)
		}
	} else {
		if !util.IsDir(overlayFileDir) {
			return fmt.Errorf("%s does not exist. Use '--parents' option to create automatically", overlayFileDir)
		}
	}

	tempFile, tempFileErr := os.CreateTemp("", "ww-overlay-edit-")
	if tempFileErr != nil {
		return fmt.Errorf("unable to create temporary file for editing: %s", tempFileErr)
	}
	defer os.Remove(tempFile.Name())
	wwlog.Debug("Using temporary file %s", tempFile.Name())

	if util.IsFile(overlayFile) {
		originalFile, openErr := os.Open(overlayFile)
		if openErr != nil {
			return fmt.Errorf("unable to open %s: %s", overlayFile, openErr)
		}
		if _, err := io.Copy(tempFile, originalFile); err != nil {
			return fmt.Errorf("unable to copy %s to %s for editing: %s", originalFile.Name(), tempFile.Name(), err)
		}
		originalFile.Close()
	} else if filepath.Ext(overlayFile) == ".ww" {
		if _, err := tempFile.Write([]byte(initialTemplate)); err != nil {
			return fmt.Errorf("unable to write to %s: %s", tempFile.Name(), err)
		}
	}
	tempFile.Close()

	var startTime time.Time
	if fileInfo, err := os.Stat(tempFile.Name()); err != nil {
		return fmt.Errorf("unable to stat %s: %s", tempFile.Name(), err)
	} else {
		startTime = fileInfo.ModTime()
	}

	editor := os.Getenv("EDITOR")
	if editor == "" {
		editor = "/bin/vi"
	}
	if editorErr := util.ExecInteractive(editor, tempFile.Name()); editorErr != nil {
		return fmt.Errorf("editor process exited with an error: %s", editorErr)
	}

	if fileInfo, err := os.Stat(tempFile.Name()); err != nil {
		return fmt.Errorf("unable to stat %s: %s", tempFile.Name(), err)
	} else {
		if startTime == fileInfo.ModTime() {
			wwlog.Debug("No change detected. Not updating overlay.")
			os.Exit(0)
		}
	}

	// try renaming the tempfile to overlayfile first
	err := os.Rename(tempFile.Name(), overlayFile)
	if err != nil {
		// if it fails, which probably means that they exists on different partitions
		// fallback to data copy
		wwlog.Debug("Unable to rename temp file: %s to overlay file: %s, try copying the data", tempFile.Name(), overlayFile)
		cerr := util.CopyFile(tempFile.Name(), overlayFile)
		if cerr != nil {
			return fmt.Errorf("unable to copy data from temp file: %s to target file: %s, err: %s", tempFile.Name(), overlayFile, err)
		}
	}

	return nil
}
