#!/bin/bash
set -e

if [[ "$1" == "sleep" ]]; then
	sleep 1000000
fi

# Replace placeholders in warewulf.conf
sed -i "s/{{WW_IPADDR}}/$WW_IPADDR/g" /etc/warewulf/warewulf.conf
sed -i "s/{{WW_NETMASK}}/$WW_NETMASK/g" /etc/warewulf/warewulf.conf
sed -i "s/{{WW_NETWORK}}/$WW_NETWORK/g" /etc/warewulf/warewulf.conf
sed -i "s/{{WW_DHCP_START}}/$WW_DHCP_START/g" /etc/warewulf/warewulf.conf
sed -i "s/{{WW_DHCP_END}}/$WW_DHCP_END/g" /etc/warewulf/warewulf.conf
sed -i "s/{{WW_NET_PREFIX}}/$WW_NET_PREFIX/g" /etc/warewulf/warewulf.conf


# Configure wulf to use volume dirs.
# Fail if we don't have a separate volume at /vol
if ! mountpoint -q /vol; then
	echo "Expected volume mount at /vol; found regular dir. Add a separate volume mount /vol and rerun container."
	echo "Aborting."
	exit 1
else
	if [[ -d /var/lib/warewulf ]]; then
		mv /var/lib/warewulf /var/lib/warewulf.local
		ln -s /vol/warewulf /var/lib/warewulf
	fi
	if [[ -d /vol/warewulf/etc ]] && [[ -f /vol/warewulf/etc/nodes.conf ]] && [[ -d /vol/warewulf/etc/keys ]]; then
		mv /etc/warewulf /etc/warewulf.local
		ln -s /vol/warewulf/etc /etc/warewulf
	else
		# first run, vol/warewulf/etc empty
		rsync -av /etc/warewulf/* /vol/warewulf/etc/
		mv /etc/warewulf /etc/warewulf.local
		ln -s /vol/warewulf/etc /etc/warewulf
	fi
fi

# Enable nfs
if [[ $SERVE_NFS -eq 1 ]]; then
	echo "SERVE_NFS=1, letting warewulf manage NFS"
	sed -i '/^nfs:/{n;s/enabled: false/enabled: true/;}' /etc/warewulf/warewulf.conf
else
	echo "SERVE_NFS=0 or unset, NFS will not be served from the container."
	sed -i '/^nfs:/{n;s/enabled: .*/enabled: false/;}' /etc/warewulf/warewulf.conf
fi

# Prepare dirs (never ran container using this volume)
for dir in chroots provision overlays; do
	if [[ ! -d /var/lib/warewulf/$dir ]]; then
		mkdir /var/lib/warewulf/$dir
	fi
done

for dir in warewulf dhcp ganesha tftp; do
	if [[ ! -d /vol/logs/$dir ]]; then
		mkdir -p /vol/logs/$dir
	fi
done



# SLURM prep
# setup munge key if needed
if [[ ! -f /etc/munge/munge.key ]]; then
	sudo -u munge mungekey
fi
if [[ ! -d /run/munge ]]; then
	mkdir /run/munge && chown munge:munge /run/munge
fi

# setup slurm config
if [[ -d /opt/slurm ]]; then
	groupadd slurm && useradd -g slurm slurm && \
	mkdir -p /run/munge && chown munge:munge /run/munge && \
	mkdir -p /var/log/slurm && mkdir -p /run/slurm && \
	chown slurm:slurm /var/log/slurm && chown slurm:slurm /run/slurm && \
	chown -R slurm:slurm /opt/slurm  && \
	echo 'PATH=$PATH:/opt/slurm/sbin:/opt/slurm/bin' >> /root/.bashrc
	chown slurm:slurm /opt/slurm/etc/slurm.conf
	echo "Found slurm, adding to supervisor."
	sed -i "s/{{SLURM_STORAGE_HOST}}/$SLURM_STORAGE_HOST/g" /opt/slurm/etc/slurm.conf
	sed -i "s/{{SLURM_SLURMCTLD_HOST}}/$SLURM_SLURMCTLD_HOST/g" /opt/slurm/etc/slurm.conf
	cat <<SLURM_EOF >> /etc/supervisor/conf.d/supervisord.conf
[program:munge]
command=/usr/sbin/munged -F
autostart=true
autorestart=true
user=munge

[program:slurmctld]
command=/opt/slurm/sbin/slurmctld -D
stdout_logfile=/vol/logs/slurm/slurmctld.out
stderr_logfile=/vol/logs/slurm/slurmctld.err
autostart=true
autorestart=true
user=slurm
SLURM_EOF

	if [[ -n "$SLURM_DBD_HOST" ]]; then
		chown slurm:slurm /opt/slurm/etc/slurmdbd.conf
		# todo insert test for storage (mysql) server, consider failing if it isn't up
		sed -i "s/{{SLURM_DBD_HOST}}/$SLURM_DBD_HOST/g" /opt/slurm/etc/slurmdbd.conf
		sed -i "s/{{SLURM_STORAGE_HOST}}/$SLURM_STORAGE_HOST/g" /opt/slurm/etc/slurmdbd.conf
		sed -i "s/{{SLURM_STORAGE_PASS}}/$SLURM_STORAGE_PASS/g" /opt/slurm/etc/slurmdbd.conf
		echo "AccountingStorageType=accounting_storage/slurmdbd" >> /opt/slurm/etc/slurm.conf
	cat <<SLURM_DBD_EOF >> /etc/supervisor/conf.d/supervisord.conf

[program:slurmdbd]
command=/opt/slurm/sbin/slurmdbd -D
stdout_logfile=/vol/logs/slurm/slurmdbd.out
stderr_logfile=/vol/logs/slurm/slurmdbd.err
autostart=true
autorestart=true
user=slurm
SLURM_DBD_EOF
	fi

	if [[ ! -d /vol/logs/slurm ]]; then
		mkdir -p /vol/logs/slurm && chown slurm:slurm /vol/logs/slurm
	fi
	
	if [[ ! -d /vol/slurm/statesave ]]; then
		mkdir -p /vol/slurm/statesave && chown -R slurm:slurm /vol/slurm
	fi
fi




# Start supervisord to manage services
/usr/bin/supervisord -c /etc/supervisor/supervisord.conf &
supervisor_ready=0
# we have to wait for the supervisor socket before running wwctl configure
for i in {1..5}; do
	if [[ ! -S /var/run/supervisor.sock ]]; then
		sleep 1
	else
		supervisor_ready=1
		break
	fi
done
if [[ $supervisor_ready -ne 1 ]]; then
	echo "Didn't find /var/run/supervisor.sock - assuming supervisor failure, aborting."
	exit 1
fi

# Configure ww services
ww_configured=0
for i in $(seq 1 5); do
	if [[ $(ps -ef | grep 'wwctl server') ]]; then
		wwctl configure --all | tee -a /vol/logs/warewulf/wulf.log
		ww_configured=1
		break
	fi
done


if [[ $ww_configured -eq 0 ]]; then
	echo "Couldn't configure warewulf!"
	pkill supervisord
	exit 1
fi

wait

