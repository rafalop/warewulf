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
fi
# Prepare dirs (never ran container using this volume)
for dir in chroots provision overlays; do
	if [[ ! -d /var/lib/warewulf/$dir ]]; then
		mkdir /var/lib/warewulf/$dir
	fi
done

# Start supervisord to manage services
/usr/bin/supervisord -c /etc/supervisor/supervisord.conf &

# Configure ww services
ww_configured=0
for i in $(seq 1 5); do
	if [[ $(ps -ef | grep 'wwctl server') ]]; then
		wwctl configure --all | tee -a /vol/warewulf/wulf.log
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

