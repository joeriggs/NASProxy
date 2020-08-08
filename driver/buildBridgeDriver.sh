#!/bin/bash

################################################################################
# Build the Proxy Bridge driver on the local computer.
################################################################################

DRIVER_NAME=proxy_bridge

readonly BLD_DIR=$( cd `dirname ${0}`    && echo ${PWD} )
readonly TOP_DIR=$( cd ${BLD_DIR}/..     && echo ${PWD} )

################################################################################
################################################################################
# Processing starts here.
################################################################################
################################################################################

echo "Building the bridge driver:"

########################################
# Initialize some stuff before we start building.
echo "  Initialization:"

readonly LOG=/tmp/`basename ${0}`.log
echo -n "    Initialize log file (${LOG}) ... "
rm -f ${LOG} &> /dev/null
[ $? -ne 0 ] && echo "Unable to delete old log file." && exit 1
touch ${LOG} &> /dev/null
[ $? -ne 0 ] && echo "Unable to create empty log file." && exit 1
echo "Pass."

# Load our print utilities.
echo -n "    Loading print utilities library ... "
readonly PRINT_UTILS_FILE=${TOP_DIR}/lib/printUtils
[ ! -f ${PRINT_UTILS_FILE} ] && echo "File not found." && exit 1
. ${PRINT_UTILS_FILE}
[ $? -ne 0 ] && echo "Fail." && exit 1 ; printResult ${RESULT_PASS}

# Load our build utilities.
echo -n "    Loading build utilities library ... "
readonly BUILD_UTILS_FILE=${TOP_DIR}/lib/buildUtils
[ ! -f ${BUILD_UTILS_FILE} ] && echo "File not found." && exit 1
. ${BUILD_UTILS_FILE}
[ $? -ne 0 ] && echo "Fail." && exit 1 ; printResult ${RESULT_PASS}

buildUtilsInit 4

# CD to the build directory.
echo -n "    CD to build dir ... "
cd ${BLD_DIR} &> ${LOG}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

echo ""

########################################
# Go build it.
echo "  Build driver:"

readonly SWITCHES="-D_REENTRANT -Wall -W -Wno-sign-compare -Wmissing-declarations -Wwrite-strings -DFE_OPTIMIZE_HEADER -DKEY_SET_PER_FILE -DDEBUG -DOVERLAY_MOUNT -Wno-unused -I . -I /usr/local/include -g -O0 -fno-strict-aliasing -MD -MP -c"

echo -n "    Compiling ... "
gcc ${SWITCHES} -D_FILE_OFFSET_BITS=64 -MT ${DRIVER_NAME}.o -o ${DRIVER_NAME}.o ${DRIVER_NAME}.c &>> ${LOG}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

echo -n "    Linking ... "
gcc -o${DRIVER_NAME} ${DRIVER_NAME}.o -lfuse3 -lcrypto -lz -lc -lpthread -lrt -ldl &>> ${LOG}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

echo -n "    Cleanup ... "
rm -f ${DRIVER_NAME}.d ${DRIVER_NAME}.o &> /dev/null
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

echo ""
printResult ${RESULT_PASS} "  `basename ${0}` Success.\n"
exit 0

