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
# Boiler plate init.  Do this at the beginning of all of the proxy scripts.
################################################################################
echo "Initialization:"

readonly LOG=/tmp/`basename ${0}`.log
echo -n "  Initialize log file (${LOG}) ... "
rm -f ${LOG} &> /dev/null
[ $? -ne 0 ] && echo "Unable to delete old log file." && exit 1
touch ${LOG} &> /dev/null
[ $? -ne 0 ] && echo "Unable to create empty log file." && exit 1
echo "Pass."

# Load our common utilities.
echo -n "  Loading common utilities library ... "
readonly COMMMON_UTILS_FILE=$( cd `dirname ${0}`/.. && echo ${PWD} )/lib/commonUtils
[ ! -f ${COMMMON_UTILS_FILE} ] && echo "File not found." && exit 1
. ${COMMMON_UTILS_FILE}
[ $? -ne 0 ] && echo "Fail." && exit 1 ; echo "Pass."

commonInitialization ${LOG} 0

echo ""

################################################################################
# End of boiler plate init.
################################################################################

################################################################################
# Configure the local IP address.
################################################################################
configIP() {
	echo    "IP Configuration:"
	read -p "  IP Address [${PROXY_NETWORK_IP_ADDR_NEW}]: "
	PROXY_NETWORK_IP_ADDR_NEW=${REPLY:-$PROXY_NETWORK_IP_ADDR_NEW}
	read -p "  Netmask    [${PROXY_NETWORK_IP_NETMASK_NEW}]: "
	PROXY_NETWORK_IP_NETMASK_NEW=${REPLY:=$PROXY_NETWORK_IP_NETMASK_NEW}
	read -p "  Gateway    [${PROXY_NETWORK_IP_GATEWAY_NEW}]: "
	PROXY_NETWORK_IP_GATEWAY_NEW=${REPLY:=$PROXY_NETWORK_IP_GATEWAY_NEW}
	echo ""
}

################################################################################
# Configure the information that we need in order to talk to our key manager.
################################################################################
configKeyManager() {
	echo    "Key Manager:"
	read -p "  IP Address:  [${KS_IP_NEW}] "
	KS_IP_NEW=${REPLY:=$KS_IP_NEW}
	read -p "  Port Number: [${KS_PORT_NEW}] "
	KS_PORT_NEW=${REPLY:=$KS_PORT_NEW}
	read -p "  Username:    [${KS_USERNAME_NEW}] "
	KS_USERNAME_NEW=${REPLY:=$KS_USERNAME_NEW}
	FAKE_PASSWORD_STR="********" ; [ -z "${KS_PASSWORD_NEW}" ] && FAKE_PASSWORD_STR=""
	read -s -p "  Password:    [${FAKE_PASSWORD_STR}] "
	KS_PASSWORD_NEW=${REPLY:=$KS_PASSWORD_NEW}
	echo "" ; echo ""
}

################################################################################
# Configure the information that we need in order to configure this proxy on
# the key manager.
################################################################################
configProxy() {
	echo    "Proxy:"
	read -p "  Name:          [${PROXY_NAME_NEW}] "
	PROXY_NAME_NEW=${REPLY:=$PROXY_NAME_NEW}
	read -p "  Port:          [${PROXY_PORT_NEW}] "
	PROXY_PORT_NEW=${REPLY:=$PROXY_PORT_NEW}
	[ -z "${PROXY_ACCESS_POLICY_NEW}" ] && PROXY_ACCESS_POLICY_NEW="Default_Decrypt_and_Encrypt_for_Linux"
	read -p "  Access Policy: [${PROXY_ACCESS_POLICY_NEW}] "
	PROXY_ACCESS_POLICY_NEW=${REPLY:=$PROXY_ACCESS_POLICY_NEW}
	read -p "  Access Key:    [${PROXY_ACCESS_KEY_NEW}] "
	PROXY_ACCESS_KEY_NEW=${REPLY:=$PROXY_ACCESS_KEY_NEW}
	echo ""
}

################################################################################
# Gather the information that we need in order to join this proxy to a Windows
# Domain.
################################################################################
configDomain() {
	echo       "Domain Controller:"
	read -p    "  Domain:      [${DOMAIN_NEW}] "
	DOMAIN_NEW=${REPLY:=$DOMAIN_NEW}
	read -p    "  Realm:       [${DOMAIN_REALM_NEW}] "
	DOMAIN_REALM_NEW=${REPLY:=$DOMAIN_REALM_NEW}
	read -p    "  Hostname:    [${DOMAIN_CONTROLLER_HOSTNAME_NEW}] "
	DOMAIN_CONTROLLER_HOSTNAME_NEW=${REPLY:=$DOMAIN_CONTROLLER_HOSTNAME_NEW}
	read -p    "  IP Address:  [${DOMAIN_CONTROLLER_IP_NEW}] "
	DOMAIN_CONTROLLER_IP_NEW=${REPLY:=$DOMAIN_CONTROLLER_IP_NEW}
	read -p    "  Username:    [${DOMAIN_USERNAME_NEW}] "
	DOMAIN_USERNAME_NEW=${REPLY:=$DOMAIN_USERNAME_NEW}
	FAKE_PASSWORD_STR="********" ; [ -z "${DOMAIN_PASSWORD_NEW}" ] && FAKE_PASSWORD_STR=""
	read -s -p "  Password:    [${FAKE_PASSWORD_STR}] "
	DOMAIN_PASSWORD_NEW=${REPLY:=$DOMAIN_PASSWORD_NEW}
	echo "" ; echo ""
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
	echo -n "Saving configuration file ... "

	cat > ${NAS_PROXY_CONF_FILE} << EOF
readonly PROXY_CONFIG_FILE_VERSION=1.0

readonly PROXY_NETWORK_IP_ADDR=${PROXY_NETWORK_IP_ADDR_NEW}
readonly PROXY_NETWORK_IP_NETMASK=${PROXY_NETWORK_IP_NETMASK_NEW}
readonly PROXY_NETWORK_IP_GATEWAY=${PROXY_NETWORK_IP_GATEWAY_NEW}

readonly KS_IP=${KS_IP_NEW}
readonly KS_PORT=${KS_PORT_NEW}
readonly KS_USERNAME=${KS_USERNAME_NEW}
readonly KS_PASSWORD=${KS_PASSWORD_NEW}

readonly PROXY_NAME=${PROXY_NAME_NEW}
readonly PROXY_NETWORK_SHARE_PROFILE=NSP-${PROXY_NAME_NEW}
readonly PROXY_PORT=${PROXY_PORT_NEW}
readonly PROXY_ACCESS_POLICY=${PROXY_ACCESS_POLICY_NEW}
readonly PROXY_ACCESS_KEY=${PROXY_ACCESS_KEY_NEW}

readonly DOMAIN=${DOMAIN_NEW}
readonly DOMAIN_REALM=${DOMAIN_REALM_NEW}
readonly DOMAIN_CONTROLLER_HOSTNAME=${DOMAIN_CONTROLLER_HOSTNAME_NEW}
readonly DOMAIN_CONTROLLER=${DOMAIN_CONTROLLER_HOSTNAME_NEW}.${DOMAIN_REALM_NEW}
readonly DOMAIN_CONTROLLER_IP=${DOMAIN_CONTROLLER_IP_NEW}
readonly DOMAIN_USERNAME=${DOMAIN_USERNAME_NEW}
readonly DOMAIN_PASSWORD=${DOMAIN_PASSWORD_NEW}

################################################################################
# These values are used by the proxy.  They have nothing to do with the customer.
################################################################################
readonly BRIDGE_DRIVER_NAME=proxy_bridge
readonly BRIDGE_DRIVER_PATH=/usr/local/bin/\${BRIDGE_DRIVER_NAME}

readonly PROXY_DATABASE=/etc/safenet/config/proxy/db

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
# POST-BOILER-PLATE PROCESSING STARTS HERE
################################################################################
################################################################################

# Load the current configuration into temporary variables (that we can write).
echo -n "Load config into temporary variables ... "

PROXY_NETWORK_IP_ADDR_NEW=${PROXY_NETWORK_IP_ADDR}
PROXY_NETWORK_IP_NETMASK_NEW=${PROXY_NETWORK_IP_NETMASK}
PROXY_NETWORK_IP_GATEWAY_NEW=${PROXY_NETWORK_IP_GATEWAY}

KS_IP_NEW=${KS_IP}
KS_PORT_NEW=${KS_PORT}
KS_USERNAME_NEW=${KS_USERNAME}
KS_PASSWORD_NEW=${KS_PASSWORD}

PROXY_NAME_NEW=${PROXY_NAME}
PROXY_NETWORK_SHARE_PROFILE_NEW=NSP-${PROXY_NAME}
PROXY_PORT_NEW=${PROXY_PORT}
PROXY_ACCESS_POLICY_NEW=${PROXY_ACCESS_POLICY}
PROXY_ACCESS_KEY_NEW=${PROXY_ACCESS_KEY}

DOMAIN_NEW=${DOMAIN}
DOMAIN_REALM_NEW=${DOMAIN_REALM}
DOMAIN_CONTROLLER_HOSTNAME_NEW=${DOMAIN_CONTROLLER_HOSTNAME}
DOMAIN_CONTROLLER_NEW=${DOMAIN_CONTROLLER_HOSTNAME}.${DOMAIN_REALM}
DOMAIN_CONTROLLER_IP_NEW=${DOMAIN_CONTROLLER_IP}
DOMAIN_USERNAME_NEW=${DOMAIN_USERNAME}
DOMAIN_PASSWORD_NEW=${DOMAIN_PASSWORD}

printResult ${RESULT_PASS}

echo ""

# Loop until they quit.
FINISHED=0
while [ ${FINISHED} -eq 0 ]; do
	echo "1 - Configure IP address."
	echo "2 - Configure Key Manager access."
	echo "3 - Configure Proxy on Key Manager."
	echo "4 - Configure Domain Controller access."
	echo "x - Logout."
	read -p "Enter option (1, 2, 3, 4, or x): "

	case ${REPLY^} in
	1) configIP         ;;
	2) configKeyManager ;;
	3) configProxy      ;;
	4) configDomain     ;;
	X) FINISHED=1       ;;
	esac
done

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
