#!/bin/bash

################################################################################
# Build everything from scratch.  The final result is an OVA file that can be
# deployed onto an ESXi 5 server.
################################################################################

export TOP_DIR=$( cd `dirname ${0}` && echo ${PWD} )
readonly DRIVER_BUILD_SCRIPT=${TOP_DIR}/driver/buildBridgeDriver.sh
readonly RPM_BUILD_SCRIPT=${TOP_DIR}/RPM/buildRPM.sh
readonly ISO_BUILD_SCRIPT=${TOP_DIR}/ISO/buildISO.sh

########################################
# Initialize some stuff before we start building.
echo "Initialization:"

readonly LOG=/tmp/`basename ${0}`.log
echo -n "  Initialize log file (${LOG}) ... "
rm -f ${LOG} &> /dev/null
[ $? -ne 0 ] && echo "Unable to delete old log file." && exit 1
touch ${LOG} &> /dev/null
[ $? -ne 0 ] && echo "Unable to create empty log file." && exit 1
echo "Pass."

# Load our print utilities.
echo -n "  Loading print utilities library ... "
readonly PRINT_UTILS_FILE=${TOP_DIR}/lib/printUtils
[ ! -f ${PRINT_UTILS_FILE} ] && echo "File not found." && exit 1
. ${PRINT_UTILS_FILE}
[ $? -ne 0 ] && echo "Fail." && exit 1 ; printResult ${RESULT_PASS}

# Load our configuration utilities.
echo -n "  Loading config utilities library ... "
readonly CONFIG_UTILS_FILE=${TOP_DIR}/lib/configUtils
[ ! -f ${CONFIG_UTILS_FILE} ] && echo "File not found." && exit 1
. ${CONFIG_UTILS_FILE}
[ $? -ne 0 ] && echo "Fail." && exit 1 ; printResult ${RESULT_PASS}

echo ""

# Load our build conf file.
loadConfigFile

########################################
# Locate the build scripts.
echo -n "Locate build scripts ... "
[ ! -f ${DRIVER_BUILD_SCRIPT} ] && printResult ${RESULT_FAIL} "Can't find ${DRIVER_BUILD_SCRIPT}\n" && exit 1
[ ! -f ${RPM_BUILD_SCRIPT}    ] && printResult ${RESULT_FAIL} "Can't find ${RPM_BUILD_SCRIPT}\n"    && exit 1
[ ! -f ${ISO_BUILD_SCRIPT}    ] && printResult ${RESULT_FAIL} "Can't find ${ISO_BUILD_SCRIPT}\n"    && exit 1
printResult ${RESULT_PASS}
echo ""

########################################
# Build the proxy_bridge driver.
${DRIVER_BUILD_SCRIPT}
[ $? -ne 0 ] && exit 1
echo ""

########################################
# Build the RPM file that essentially represents this version of PF Proxy.
${RPM_BUILD_SCRIPT}
[ $? -ne 0 ] && exit 1
echo ""

########################################
# Build the ISO.  It's the actual VM that is loaded into ESXi.
${ISO_BUILD_SCRIPT}
[ $? -ne 0 ] && exit 1
echo ""

########################################
# Done.  Success.
printResult ${RESULT_PASS} "Success.\n"
exit 0

