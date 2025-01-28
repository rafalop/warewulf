package debian_interfaces

import (
	"bytes"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/warewulf/warewulf/internal/app/wwctl/overlay/show"
	"github.com/warewulf/warewulf/internal/pkg/testenv"
	"github.com/warewulf/warewulf/internal/pkg/wwlog"
)

func Test_wickedOverlay(t *testing.T) {
	env := testenv.New(t)
	defer env.RemoveAll()
	env.ImportFile("var/lib/warewulf/overlays/debian.interfaces/rootfs/etc/network/interfaces.d/default.ww", "../rootfs/etc/network/interfaces.d/default.ww")

	tests := []struct {
		name       string
		nodes_conf string
		args       []string
		log        string
	}{
		{
			name:       "debian.interfaces",
			nodes_conf: "nodes.conf",
			args:       []string{"--render", "node1", "debian.interfaces", "etc/network/interfaces.d/default.ww"},
			log:        debian_interfaces,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			env.ImportFile("etc/warewulf/nodes.conf", tt.nodes_conf)
			cmd := show.GetCommand()
			cmd.SetArgs(tt.args)
			stdout := bytes.NewBufferString("")
			stderr := bytes.NewBufferString("")
			logbuf := bytes.NewBufferString("")
			cmd.SetOut(stdout)
			cmd.SetErr(stderr)
			wwlog.SetLogWriter(logbuf)
			err := cmd.Execute()
			assert.NoError(t, err)
			assert.Empty(t, stdout.String())
			assert.Empty(t, stderr.String())
			assert.Equal(t, tt.log, logbuf.String())
		})
	}
}

const debian_interfaces string = `backupFile: true
writeFile: true
Filename: default

# This file is autogenerated by warewulf
allow-hotplug wwnet0
iface wwnet0 inet static
  address 192.168.3.21
  netmask 255.255.255.0
  gateway 192.168.3.1
  mtu 1500

backupFile: true
writeFile: true
Filename: secondary
# This file is autogenerated by warewulf
allow-hotplug wwnet1
iface wwnet1 inet static
  address 192.168.3.22
  netmask 255.255.255.0
  gateway 192.168.3.1
  mtu 9000
  up ip route add 192.168.1.0/24 via 192.168.3.254 dev wwnet1
`
