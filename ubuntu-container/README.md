# Ubuntu based container
## Description
This container prepares warewulf, dhcp, tftp and nfs ganesha and slurm into a single bundle to serve using Docker or K8s.

## Notes on slurm
Slurm is optional, and has some very specific pre-requirements. These instructions assume you know how to build slurm and openmpi to work together.
- Build openmpi with prefix=/opt/ompi
- Build slurm with prefix=/opt/slurm
- Tarball everything required for slurm
- Set your environment variable SLURM_TARBALL={of slurm tgz} before running docker build. If you don't supply this, the warewulf container will simply exclude slurm.
- The docker build will unpack ompi and slurm to /opt in the container, and /opt will be served via NFS so it can be used on the compute nodes. Note, it is not intended for slurmd to run inside docker on the compute nodes. Slurmctld and slurmdbd run in this container for bundling and HA purposes (kubernetes). On the compute nodes, you should set up regular systemd services using warewulf overlays or in the warewulf image, with the executable pointing to the binary in /opt/slurm (served from NFS).

## Building the container
This will compile warewulf using this local repo/source, and package the other components (nfs, dhcp, tftp, slurm) into the container. **Build from the with CWD=top level repo dir, not from ubuntu-container dir**.
No slurm:
```
sudo docker build . --network=host -t wulf:latest -f ubuntu-container/Dockerfile
```
With slurm (tarball packed as specified above):
```
sudo docker build . --build-arg SLURM_TARBALL=ubuntu-container/slurm/slurm24.11.1.tgz --network=host -t wulf-slurm:latest -f ubuntu-container/Dockerfile-slurm
```

## Running the container
### Storage requirements
A persistent volume needs to be supplied and mounted at /vol in the container. This is to store logs, and persistent data (eg. warewulf images etc). Since it will storage full operating system images, it is recommended this is large - eg. 50G+.
### Required variables
At a minimum, these vars are required to be set for the warewulf container to operate:
WW_IPADDR={ip address to serve warewulf on, host ip, or floating ip}
WW_NETMASK={netmask of above}
WW_NETWORK={the base ip of the network, eg. 192.168.0.0}
WW_DHCP_START={first ip of dhcp range to reserve for warewulf boot}
WW_DHCP_END={last ip of dhcp range to reserve for warewulf boot}
WW_NET_PREFIX=24

### Slurm
Assuming your docker build included slurm, you will need to set SLURM__SLURMCTLD_HOST (should be same as WW_IPADDR).

### Slurm accounting (slurmdbd)
Slurmdbd is optional, and will only run if you supply environment variables SLURM_DBD_HOST, SLURM_STORAGE_HOST, and SLURM_STORAGE_PASS variables. Otherwise it will still run slurmctld just without accounting. In addition, you will have to have a pre-existing mysql/mariadb server with the `slurm_acct_db` database created along with the `slurm` user, and SLURM_STORAGE_PASS for that user.
SLURM_DBD_HOST={ip address where slurmdbd is running, typically same as WW_IPADDR}
SLURM_STORAGE_HOST={ip of mysql/mariadb server}
SLURM_STORAGE_PASS={password for accessing the mariadb server}

### Run command example (Docker)
Assuming the above variables are in file called `env.list`, and your persistent volume is just a directory:
```
sudo docker run --privileged -d --name wulf --env-file env.list -v /srv/vol:/vol --network=host wulf:latest
```
