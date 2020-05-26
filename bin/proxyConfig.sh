#!/bin/bash

################################################################################
# Make sure they have a config file before proceeding.  We need to do this
# before our boiler plate initialization.  Otherwise, the boiler plate will
# fail if there isn't a config file on this proxy.
################################################################################

echo ""

# We're using the proxy's config file.
NAS_PROXY_CONF_FILE=/etc/NASProxy.conf
echo    "Prepare config file (${NAS_PROXY_CONF_FILE}):"
echo -n "  Look for config file ... "
if [ -f ${NAS_PROXY_CONF_FILE} ]; then
	echo "Found."
else
	echo "Missing."
	echo -n "  Create empty config file ... "
	touch ${NAS_PROXY_CONF_FILE}
	[ $? -ne 0 ] && echo "Fail." && exit 1 ; echo "Pass."
fi

echo ""

################################################################################
# Initialize the log file.  Don't exit if it fails.  It's a bummer if we can't
# have a log file, but it's certainly not a fatal error.
readonly LOG=/tmp/`basename ${0}`.log
rm -f ${LOG} &> /dev/null
[ $? -ne 0 ] && echo "Unable to delete old log file."
touch ${LOG} &> /dev/null
[ $? -ne 0 ] && echo "Unable to create empty log file."

# Load our common utilities.
readonly COMMMON_UTILS_FILE=$( cd `dirname ${0}`/.. && echo ${PWD} )/lib/commonUtils
[ ! -f ${COMMMON_UTILS_FILE} ] && echo "${COMMON_UTILS_FILE} not found." && exit 1
. ${COMMMON_UTILS_FILE}

commonInitialization ${LOG} 0

IP_MODIFIED=0

################################################################################
# Test the IP address configuration by attempting to ping the specified gateway.
#
# Input:
#   The IP address is configured.
#
# Output:
#   0 - success.
#   1 - failure.
################################################################################
pingGateway() {
	local RETCODE=0

	echo -n "Pinging ${PROXY_NETWORK_IP_GATEWAY} ... "
	ping -c 4 ${PROXY_NETWORK_IP_GATEWAY} &> ${LOG}
	if [ $? -ne 0 ]; then
	       printResult ${RESULT_FAIL}
	       RETCODE=1
	else
		printResult ${RESULT_PASS}
	fi

	read -p "Press <ENTER> to continue." ; echo ""
	return ${RETCODE}
}

################################################################################
# Get new IP address information from the user.
################################################################################
ipAddrGet() {
	echo    "IP Configuration:"
	read -p "  IP Address [${PROXY_NETWORK_IP_ADDR}]: "
	PROXY_NETWORK_IP_ADDR_NEW=${REPLY:-$PROXY_NETWORK_IP_ADDR}
	read -p "  Netmask    [${PROXY_NETWORK_IP_NETMASK}]: "
	PROXY_NETWORK_IP_NETMASK_NEW=${REPLY:=$PROXY_NETWORK_IP_NETMASK}
	read -p "  Gateway    [${PROXY_NETWORK_IP_GATEWAY}]: "
	PROXY_NETWORK_IP_GATEWAY_NEW=${REPLY:=$PROXY_NETWORK_IP_GATEWAY}
	echo ""

	if [ "${PROXY_NETWORK_IP_ADDR}"    != "${PROXY_NETWORK_IP_ADDR_NEW}"    ] || \
	   [ "${PROXY_NETWORK_IP_NETMASK}" != "${PROXY_NETWORK_IP_NETMASK_NEW}" ] || \
	   [ "${PROXY_NETWORK_IP_GATEWAY}" != "${PROXY_NETWORK_IP_GATEWAY_NEW}" ]; then
		IP_MODIFIED=1

		PROXY_NETWORK_IP_ADDR=${PROXY_NETWORK_IP_ADDR_NEW}
		PROXY_NETWORK_IP_NETMASK=${PROXY_NETWORK_IP_NETMASK_NEW}
		PROXY_NETWORK_IP_GATEWAY=${PROXY_NETWORK_IP_GATEWAY_NEW}

		unset PROXY_NETWORK_IP_ADDR_NEW PROXY_NETWORK_IP_NETMASK_NEW PROXY_NETWORK_IP_GATEWAY_NEW
	fi

	[ ${IP_MODIFIED} -eq 1 ] && ipAddrSet && IP_MODIFIED=0
}

################################################################################
# Configure the local IP address.
#
# Input:
#   The new environment variables that were specified by the user.
#
# Output:
#   0 - success.
#   1 - failure.
################################################################################
ipAddrSet() {
	local NET_IF=ens160

	local RETCODE=0

	# Convert the x.x.x.x netmask to a CIDR count (ex. 255.255.255.0 to /24).
	echo -n "Convert netmask to CIDR ... "
	NETMASK_CIDR=`ipcalc -p 1.1.1.1 ${PROXY_NETWORK_IP_NETMASK} | sed -n 's/^PREFIX=\(.*\)/\/\1/p'`
	if [ $? -ne 0 ]; then printResult ${RESULT_FAIL} ; RETCODE=1 ; else printResult ${RESULT_PASS} ; fi

	if [ ${RETCODE} -eq 0 ]; then
		echo -n "Set IP address and netmask ... "
		nmcli con mod ${NET_IF} ipv4.address ${PROXY_NETWORK_IP_ADDR}${NETMASK_CIDR} &> ${LOG}
		if [ $? -ne 0 ]; then printResult ${RESULT_FAIL} ; RETCODE=1 ; else printResult ${RESULT_PASS} ; fi
	fi

	if [ ${RETCODE} -eq 0 ]; then
		echo -n "Set gateway ... "
		nmcli con mod ${NET_IF} ipv4.gateway ${PROXY_NETWORK_IP_GATEWAY} &> ${LOG}
		if [ $? -ne 0 ]; then printResult ${RESULT_FAIL} ; RETCODE=1 ; else printResult ${RESULT_PASS} ; fi
	fi

	if [ ${RETCODE} -eq 0 ]; then
		echo -n "Set autoconnect ... "
		nmcli con mod ${NET_IF} autoconnect yes &> ${LOG}
		if [ $? -ne 0 ]; then printResult ${RESULT_FAIL} ; RETCODE=1 ; else printResult ${RESULT_PASS} ; fi
	fi

	if [ ${RETCODE} -eq 0 ]; then
		echo -n "Down ... "
		nmcli con down ${NET_IF} &> ${LOG}
		if [ $? -ne 0 ]; then printResult ${RESULT_FAIL} ; RETCODE=1 ; else printResult ${RESULT_PASS} ; fi
	fi

	if [ ${RETCODE} -eq 0 ]; then
		echo -n "Up ... "
		nmcli con up ${NET_IF} &> ${LOG}
		if [ $? -ne 0 ]; then printResult ${RESULT_FAIL} ; RETCODE=1 ; else printResult ${RESULT_PASS} ; fi
	fi

	read -p "Press <ENTER> to continue." ; echo ""
	return ${RETCODE}
}

################################################################################
# Write a brand new copy of the config file.
#
# Input:
#   All of the variables are set to their requested values.
#
# Output:
#   None right now.
################################################################################
writeConfigFile() {
	echo "" ; echo -n "Saving configuration file ... "

	cat > ${NAS_PROXY_CONF_FILE} << EOF
PROXY_NETWORK_IP_ADDR=${PROXY_NETWORK_IP_ADDR}
PROXY_NETWORK_IP_NETMASK=${PROXY_NETWORK_IP_NETMASK}
PROXY_NETWORK_IP_GATEWAY=${PROXY_NETWORK_IP_GATEWAY}

################################################################################
# These values are used by the proxy.
################################################################################
readonly PROXY_CONFIG_FILE_VERSION=1.0

readonly BRIDGE_DRIVER_NAME=proxy_bridge
readonly BRIDGE_DRIVER_PATH=/usr/local/bin/\${BRIDGE_DRIVER_NAME}

readonly PROXY_DATABASE=/etc/NASProxy.db

# Values used when we're modifying our /etc/exports file.
readonly PERM_EXPORTS=/etc/exports
readonly TEMP_EXPORTS=/tmp/exports.tmp
readonly EXPORTS_MSG="# NAS Proxy entries."
EOF

	[ $? -ne 0 ] && printResult ${RESULT_FAIL} ; printResult ${RESULT_PASS}

	read -p "Press <ENTER> to continue."
}

################################################################################
################################################################################
# PROCESSING STARTS HERE
################################################################################
################################################################################

# Load the current configuration into temporary variables (that we can write).
echo -n "Load config into temporary variables ... "

printResult ${RESULT_PASS}

echo ""

# Loop until they quit.
FINISHED=0
while [ ${FINISHED} -eq 0 ]; do
	echo "1 - Configure IP address."
	echo "2 - Ping IP gateway."
	echo "x - Logout."
	read -p "Enter option (1, 2, or x): "

	case ${REPLY^} in
	1) ipAddrGet        ;;
	2) pingGateway      ;;
	X) FINISHED=1       ;;
	esac
done

echo ""

FINISHED=0
while [ ${FINISHED} -eq 0 ]; do
	read -p "Save changes? (y or n) "
	case ${REPLY^} in
	Y) writeConfigFile ; FINISHED=1 ;;
	N) FINISHED=1 ;;
	esac
done

printResult ${RESULT_PASS} "Success.\n"
exit 0
