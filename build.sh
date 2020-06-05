#!/bin/bash

################################################################################
# Build everything from scratch.  The final result is an OVA file that can be
# deployed onto an ESXi 5 server.
#
# We can build one of the following products:
# 1. NAS Proxy -  This git project contains all of the data required to build a
#    copy of the NAS Proxy.
#
# 2. NAS Encryptor - If you specify the environment variable NAS_ENCRYPTOR_DIR,
#    then this build tool will build the NAS Encryptor.  It will expect the
#    NAS_ENCRYPTOR_DIR to point to a directory that is a copy of the
#    NASEncryptor git project.
################################################################################

export TOP_DIR=$( cd `dirname ${0}` && echo ${PWD} )
readonly DRIVER_BUILD_SCRIPT=${TOP_DIR}/driver/buildBridgeDriver.sh
readonly RPM_BUILD_SCRIPT=${TOP_DIR}/RPM/buildRPM.sh
readonly VM_BUILD_SCRIPT=${TOP_DIR}/VM/buildVM.sh

########################################
# What are we building?
echo ""
if [ ! -z "${NAS_ENCRYPTOR_DIR}" ]; then
	echo "Building the NAS Encryptor."
else
	echo "Building the NAS Proxy."
fi
echo ""

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
readonly CONFIG_UTILS_FILE=${TOP_DIR}/lib/buildUtils
[ ! -f ${CONFIG_UTILS_FILE} ] && echo "File not found." && exit 1
. ${CONFIG_UTILS_FILE}
[ $? -ne 0 ] && echo "Fail." && exit 1 ; printResult ${RESULT_PASS}

echo ""

# Load our build conf file.
loadBuildConfigFile
echo ""

# Initialize our buildUtils library.
buildUtilsInit
[ $? -ne 0 ] && exit 1

########################################
# Locate the build scripts.
echo -n "Locate build scripts ... "
[ ! -f ${DRIVER_BUILD_SCRIPT} ] && printResult ${RESULT_FAIL} "Can't find ${DRIVER_BUILD_SCRIPT}\n" && exit 1
[ ! -f ${RPM_BUILD_SCRIPT}    ] && printResult ${RESULT_FAIL} "Can't find ${RPM_BUILD_SCRIPT}\n"    && exit 1
[ ! -f ${VM_BUILD_SCRIPT}     ] && printResult ${RESULT_FAIL} "Can't find ${VM_BUILD_SCRIPT}\n"     && exit 1
printResult ${RESULT_PASS}
echo ""

########################################
# Build the proxy_bridge driver.
${DRIVER_BUILD_SCRIPT}
[ $? -ne 0 ] && exit 1
echo ""

########################################
# Build the RPM file that essentially represents this version of the NAS Proxy.
if [ ! -z "${NAS_ENCRYPTOR_DIR}" ]; then
	NAS_ENCRYPTOR_DIR=${NAS_ENCRYPTOR_DIR} ${RPM_BUILD_SCRIPT}
else
	${RPM_BUILD_SCRIPT}
fi
[ $? -ne 0 ] && exit 1
echo ""

########################################
# Build the VM.  It's the actual VM that is loaded into ESXi.
${VM_BUILD_SCRIPT}
[ $? -ne 0 ] && exit 1
echo ""

########################################
# Done.  Success.
printResult ${RESULT_PASS} "Success.\n"
exit 0

