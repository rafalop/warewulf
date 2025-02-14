#!/bin/bash


# Generate command for adding node to warewulf including IPoIB addresses.
# Calculates a unique mapping of higher order subnet for internal IPoiB addresses
# In case we need unique internal IPs for cluster/intnet size larger than /24

NODE_NAME=""
NODE_IP=""
HWADDR=""
IPOIB_SUBNET=100.0.0.0 # /8
OUTPUT="wwcmd"
PROFILE="default"
IFACE="eno8303"
TAGS=""

# For original nodes
#IPOIB_DEVS_1=(
#'ibp27s0'
#'ibp65s0'
#'ibp84s0'
#'ibp103s0'
#'ibp157s0'
#'ibp193s0'
#'ibp211s0'
#'ibp229s0'
#)
IPOIB_DEVS_1=(
'ib0'
'ib1'
'ib2'
'ib3'
'ib4'
'ib5'
'ib6'
'ib7'
)

#ETH_DEVS_1=(
#'enp28s0f0np0'
#'enp28s0f1np1'
#)
ETH_DEVS_1=(
'eth2'
'eth3'
)

# For *XS64
#IPOIB_DEVS_2=(
#'ibp26s0'
#'ibp60s0'
#'ibp77s0'
#'ibp94s0'
#'ibp156s0'
#'ibp188s0'
#'ibp204s0'
#'ibp220s0'
#)
IPOIB_DEVS_2=(
'ib0'
'ib1'
'ib2'
'ib3'
'ib4'
'ib5'
'ib6'
'ib7'
)

#ETH_DEVS_2=(
#'enp27s0f0np0'
#'enp27s0f1np1'
#)

ETH_DEVS_2=(
'eth2'
'eth3'
)


# For L40s
IPOIB_DEVS_3=(
'ibp46s0'
'ibp47s0'
'ibp175s0'
'ibp193s0'
)


IPOIB_ADDRS=()

WEKA_DEV='ibp28s0f1'
WEKA_IP=""
WEKA_IP_PREFIX_LENGTH="19"

function print_help() {
	echo "Usage:
$0 --node-name MYNODE --node-ip X.X.X.X/YY --hwaddr AB:CD:EF:12:34:56
(hwaddr only required for ww outputs)

Optional parameters
--iface  (use non standard interface, eg. for lom2 hosts  default: $IFACE)
--tags   add arbitrary metadata for node, eg. --tags key1=val1,key2=val2
--profile  (ww profile)
--output [wwcmd|print]   (prints out warewulf commands just print resulting IPs) 
--weka-ip  (also configure this ip with the weka storage interface)
--weka-dev  (set what interface to use for weka. default: $WEKA_DEV)
--weka-ip-prefix-length  (set the ip prefix length. default: $WEKA_IP_PREFIX_LENGTH)
"
}

args=($@)
count=0
for arg in ${args[*]}
do
    pos=$(($count+1))
    case $arg in
    "--node-name")
        NODE_NAME=${args[pos]}
    ;;
    "--node-ip")
        NODE_IP=${args[pos]}
    ;;
    "--hwaddr")
        HWADDR=${args[pos]}
    ;;
    "--output")
        OUTPUT=${args[pos]}
    ;;
    "--profile")
        PROFILE=${args[pos]}
    ;;
    "--iface")
        IFACE=${args[pos]}
    ;;
    "--tags")
        TAGS=${args[pos]}
    ;;
    "--weka-dev")
        WEKA_DEV=${args[pos]}
    ;;
    "--weka-ip")
        WEKA_IP=${args[pos]}
    ;;
    "--weka-ip-prefix-length")
        WEKA_IP_PREFIX_LENGTH=${args[pos]}
    ;;
    "-h")
        print_help
	exit 0
    ;;
        *)
        :
    ;;
    esac
    count=$(($count+1))
done


if [[ "$NODE_NAME" == "" ]] || [[ "$NODE_IP" == "" ]]; then
	echo "Error - missing required parameter"
	echo
	print_help
	exit 1
fi

if [[ "$OUTPUT" != "netplan" ]] && [[ "$HWADDR" == "" ]]; then
	echo "Error - missing required parameter"
	echo
	print_help
	exit 1
fi

if [[ "$NODE_IP" != *"/"* ]]; then
	echo "Supplied IP address appears to be missing prefix length"
	echo
	print_help
	exit 1
fi

NODE_IP_PREFIX=$(echo $NODE_IP | cut -f2 -d '/')
NODE_IP=$(echo $NODE_IP | cut -f1 -d '/')

# Function to convert IP address to integer
ip_to_int() {
  local IFS=.
  local -a octets=($1)
  echo "$((octets[0] * 256**3 + octets[1] * 256**2 + octets[2] * 256 + octets[3]))"
}

# Function to convert integer to IP address
int_to_ip() {
  local ip=$1
  echo "$((ip >> 24 & 255)).$((ip >> 16 & 255)).$((ip >> 8 & 255)).$((ip & 255))"
}

# Function to generate a set of 10 unique IP addresses in the second subnet
generate_ip_set() {
  local base_ip_int=$1
  local -a ip_set=()
  #local second_subnet_base=1677721600  # 100.0.0.0 in integer
  local second_subnet_base=$(ip_to_int $IPOIB_SUBNET)  # 100.0.0.0 in integer

  ip_count_req=${#IPOIB_DEVS_1[*]}
  for i in $(seq 1 $ip_count_req); do
    ip_set+=($(int_to_ip $((second_subnet_base + base_ip_int * 10 + i))))
  done

  echo "${ip_set[@]}"
}

# Example IP in the first subnet
first_subnet_ip="$NODE_IP"
# Assume /16
IFS='.' read -r octet1 octet2 _ _ <<< "$first_subnet_ip"

# Convert the first subnet IP to integer, assume /16
first_subnet_ip_int=$(ip_to_int "$first_subnet_ip")
first_subnet_ip_int=$((first_subnet_ip_int - $(ip_to_int "$octet1.$octet2.0.0")))  # Normalize to start from 0

# Generate a set of 10 unique IP addresses in the second subnet
ip_set=$(generate_ip_set "$first_subnet_ip_int")

# Store results
for ip in $ip_set; do
	IPOIB_IPS+=("$ip")
done

# Print the results
if [[ "$OUTPUT" == "print" ]]; then
	echo "First Subnet IP: $first_subnet_ip"
	echo "Mapped IPs in Second Subnet:"
	IFS=' '
	for ip in ${IPOIB_IPS[*]}; do
		echo "  $ip"
	done
	exit 0
fi

#echo ${IPOIB_IPS[*]}
#echo ${IPOIB_DEVS}

if [[ "$OUTPUT" == "wwcmd" ]]; then
	# insert add command
	echo "wwctl node add $NODE_NAME --hwaddr $HWADDR --netdev $IFACE --netname $IFACE --ipaddr $NODE_IP --nettagadd prefix_length=${NODE_IP_PREFIX},mgt=true --profile $PROFILE $(if [[ $TAGS != "" ]]; then echo -n --tagadd $TAGS; fi)"
	# loop over ipoib devices and add each one as network dev
	if [[ $(echo "$NODE_NAME" | egrep 'XS64|X64') ]]; then
		count=0
		for dev in ${IPOIB_DEVS_2[*]}; do
			echo "wwctl node set $NODE_NAME -y --netname ${dev} --ipaddr ${IPOIB_IPS[$count]} --netdev ${dev} --nettagadd prefix_length=8,mgt=false"
			count=$((count+1))
		done
		count=1
		for dev in ${ETH_DEVS_1[*]}; do
			echo "wwctl node set $NODE_NAME -y --netname ${dev} --ipaddr $(echo 192.168.${count}0.$(echo $NODE_IP | cut -f4 -d'.')) --netdev ${dev} --nettagadd prefix_length=22,mgt=false"
			((count++))
		done
	elif [[ "$NODE_NAME" == *"A484"* ]]; then
		count=0
		for dev in ${IPOIB_DEVS_3[*]}; do
			echo "wwctl node set $NODE_NAME -y --netname ${dev} --ipaddr ${IPOIB_IPS[$count]} --netdev ${dev} --nettagadd prefix_length=8,mgt=false"
			count=$((count+1))
		done
	else
		count=0
		for dev in ${IPOIB_DEVS_1[*]}; do
			echo "wwctl node set $NODE_NAME -y --netname ${dev} --ipaddr ${IPOIB_IPS[$count]} --netdev ${dev} --nettagadd prefix_length=8,mgt=false"
			count=$((count+1))
		done
		count=1
		for dev in ${ETH_DEVS_2[*]}; do
			echo "wwctl node set $NODE_NAME -y --netname ${dev} --ipaddr $(echo 192.168.${count}0.$(echo $NODE_IP | cut -f4 -d'.')) --netdev ${dev} --nettagadd prefix_length=22,mgt=false"
			((count++))
		done
	fi
	if [[ "$WEKA_IP" != "" ]]; then
		echo "wwctl node set $NODE_NAME -y --netname ${WEKA_DEV} --ipaddr ${WEKA_IP} --netdev ${WEKA_DEV} --nettagadd prefix_length=${WEKA_IP_PREFIX_LENGTH},mgt=false"
	fi
	exit 0
	
fi

#if [[ "$OUTPUT" == "wwyaml" ]]; then
#
#fi



if [[ "$OUTPUT" == "netplan" ]]; then
	# assume .1 for gateway
	IFS='/' read -r ip_addr _ <<< "$NODE_IP"
	# Set the final octet to .1
	IFS='.' read -r octet1 octet2 octet3 octet4 <<< "$ip_addr"
	gateway="${octet1}.${octet2}.${octet3}.1"
	IFS=$'\n'
	echo -n "
network:
    version: 2
    ethernets:
        $IFACE:
            dhcp4: false
            addresses: ["${NODE_IP}/${NODE_IP_PREFIX}"]
            routes:
              - to: default
                via: $gateway
	"
	count=0
	for dev in ${IPOIB_DEVS[*]}; do
		printf "        %s:\n            addresses: [\"%s/8\"]\n" $dev ${IPOIB_IPS[$count]}
		count=$((count+1))
	done
fi	

#3QVMF14:
#  profiles:
#  - cmsg
#  network devices:
#    eno8303:
#      device: eno8303
#      hwaddr: c4:cb:e1:bb:d4:9e
#      tags:
#        prefix_length: "21"
