#!/bin/bash

################################################################################
# The script that runs when the user logs in as "admin".
################################################################################

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

# Initialize our libraries.
commonInitialization ${LOG} 0
proxyInitialization ${LOG} 0
rhelVersionInit ${LOG} 0

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
	echo "1 - Change admin password."
	echo "2 - Configure IP address."
	echo "3 - Ping IP gateway."
	echo "4 - Create a proxy entry."
	echo "5 - Remove a proxy entry."
	echo "x - Logout."
	read -p "Enter option (1 - 5, or x): "

	case ${REPLY^} in
	1) changePassword   ;;
	2) ipAddrGet        ;;
	3) pingGateway      ;;
	4) proxyAddEntry    ;;
	5) proxyRemoveEntry ;;
	X) FINISHED=1       ;;
	esac
done

echo ""

FINISHED=0
while [ ${FINISHED} -eq 0 ]; do
	read -p "Save changes? (y or n) "
	case ${REPLY^} in
	Y) saveConfigFile ; FINISHED=1 ;;
	N) FINISHED=1 ;;
	esac
done

printResult ${RESULT_PASS} "Success.\n"
exit 0
