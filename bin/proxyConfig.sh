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
readonly COMMON_UTILS_FILE=/usr/local/lib/commonUtils
[ ! -f ${COMMON_UTILS_FILE} ] && echo "${COMMON_UTILS_FILE} not found." && exit 1
. ${COMMON_UTILS_FILE}

# Load our network/IPAddr utilities.
readonly IP_ADDR_UTILS_FILE=/usr/local/lib/ipUtils
[ ! -f ${IP_ADDR_UTILS_FILE} ] && echo "${IP_ADDR_UTILS_FILE} not found." && exit 1
. ${IP_ADDR_UTILS_FILE}

# Load our proxy utilities.
readonly PROXY_UTILS_FILE=/usr/local/lib/proxyUtils
[ ! -f ${PROXY_UTILS_FILE} ] && echo "${PROXY_UTILS_FILE} not found." && exit 1
. ${PROXY_UTILS_FILE}

# Initialize our libraries.
commonInitialization ${LOG} 0
proxyInitialization ${LOG} 0

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
	echo "3 - Create a proxy entry."
	echo "x - Logout."
	read -p "Enter option (1, 2, 3, or x): "

	case ${REPLY^} in
	1) ipAddrGet        ;;
	2) pingGateway      ;;
	3) proxyAddEntry    ;;
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
