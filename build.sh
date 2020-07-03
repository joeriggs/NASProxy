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

################################################################################
IS_CLEANED=0
cleanup() {
	local RC=${1}

	[ ${IS_CLEANED} -ne 0 ] && return
	IS_CLEANED=1

	local TS_END=`date +%s`
	local SECONDS=$(( TS_END - TS_BEG ))
	local ELAPSED_HRS=$(( SECONDS / 3600 ))
	SECONDS=$(( SECONDS - ELAPSED_HRS * 3600 ))
	local ELAPSED_MIN=$(( SECONDS / 60 ))
	SECONDS=$(( SECONDS - ELAPSED_MIN * 60 ))

	# Done.  Success.
	local ELAPSED_TIME_STR="`printf \"%02d hours : %02d minutes : %02d seconds\" ${ELAPSED_HRS} ${ELAPSED_MIN} ${SECONDS}`"
	echo ""
	if [ ${RC} -eq 0 ]; then
		printResult ${RESULT_PASS} "Success (${ELAPSED_TIME_STR}).\n"
	else
		printResult ${RESULT_FAIL} "Failure (${ELAPSED_TIME_STR}).\n"
	fi
	echo ""
	exit ${RC}
}
trap "cleanup 0" EXIT
trap "cleanup 1" SIGHUP
trap "cleanup 2" SIGQUIT
trap "cleanup 3" SIGINT

# We'll display the elapsed time at the end.
TS_BEG=`date +%s`

export TOP_DIR=$( cd `dirname ${0}` && echo ${PWD} )
readonly DRIVER_BUILD_SCRIPT=${TOP_DIR}/driver/buildBridgeDriver.sh
readonly RPM_BUILD_SCRIPT=${TOP_DIR}/RPM/buildRPM.sh
readonly VM_BUILD_SCRIPT=${TOP_DIR}/VM/buildVM.sh

if [ ! -z "${NAS_ENCRYPTOR_DIR}" ]; then
	readonly BUILD_NAS_ENCRYPTOR=1
	readonly NAS_ENCRYPTOR_BUILD_SCRIPT=${NAS_ENCRYPTOR_DIR}/build.sh
else
	readonly BUILD_NAS_ENCRYPTOR=0
fi

########################################
# What are we building?
echo ""
if [ ${BUILD_NAS_ENCRYPTOR} -eq 1 ]; then
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

[ ${BUILD_NAS_ENCRYPTOR} -eq 1 ] && [ ! -f ${NAS_ENCRYPTOR_BUILD_SCRIPT} ] && printResult ${RESULT_FAIL} "Can't find ${NAS_ENCRYPTOR_BUILD_SCRIPT}\n" && exit 1
printResult ${RESULT_PASS}
echo ""

########################################
# Build the proxy_bridge driver.
${DRIVER_BUILD_SCRIPT}
[ $? -ne 0 ] && exit 1
echo ""

########################################
# Build the RPM file that essentially represents this version of the NAS Proxy.
${RPM_BUILD_SCRIPT}
[ $? -ne 0 ] && exit 1
echo ""

########################################
# Build the package that contains the NAS Encryptor.
if [ ${BUILD_NAS_ENCRYPTOR} -eq 1 ]; then
	${NAS_ENCRYPTOR_BUILD_SCRIPT}
	[ $? -ne 0 ] && exit 1
	echo ""
fi

########################################
# Build the VM.  It's the actual VM that is loaded into ESXi.
if [ ${BUILD_NAS_ENCRYPTOR} -eq 1 ]; then
	NAS_ENCRYPTOR_DIR="${NAS_ENCRYPTOR_DIR}" ${VM_BUILD_SCRIPT}
else
	${VM_BUILD_SCRIPT}
fi
[ $? -ne 0 ] && exit 1
echo ""

########################################
# Done.  Success.
exit 0

