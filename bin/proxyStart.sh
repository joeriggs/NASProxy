#!/bin/bash

################################################################################
# The systemd script that runs when the NAS Proxy is started by systemd.
################################################################################

################################################################################
# Initialize the log file.  Don't exit if it fails.  It's a bummer if we can't
# have a log file, but it's certainly not a fatal error.
readonly LOG=/var/log/`basename ${0}`.log
[ -f ${LOG} ] && mv -f ${LOG} ${LOG}.old &> /dev/null
[ $? -ne 0 ] && echo "Unable to save old log file."
touch ${LOG} &> /dev/null
[ $? -ne 0 ] && echo "Unable to create empty log file."

# Load our common utilities.
readonly COMMON_UTILS_FILE=/usr/local/lib/commonUtils
[ ! -f ${COMMON_UTILS_FILE} ] && echo "${COMMON_UTILS_FILE} not found." && exit 1
. ${COMMON_UTILS_FILE}

# Load our proxy utilities.
readonly PROXY_UTILS_FILE=/usr/local/lib/proxyUtils
[ ! -f ${PROXY_UTILS_FILE} ] && echo "${PROXY_UTILS_FILE} not found." && exit 1
. ${PROXY_UTILS_FILE}

# Initialize our libraries.
commonInitialization ${LOG} 1
proxyInitialization ${LOG} 1

################################################################################
################################################################################
# PROCESSING STARTS HERE
################################################################################
################################################################################

echo "This is proxyStart.sh running."

while true; do
	sleep 1
done

exit 0

