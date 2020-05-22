#!/bin/bash

################################################################################
# Build the RPM file that represents the current release of the NAS Proxy.
################################################################################

readonly BLD_DIR=$( cd `dirname ${0}`    && echo ${PWD} )
readonly TOP_DIR=$( cd ${BLD_DIR}/..     && echo ${PWD} )

echo "Building the RPM file:"

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

# Load our configuration utilities.
echo -n "  Loading config utilities library ... "
readonly CONFIG_UTILS_FILE=${TOP_DIR}/lib/configUtils
[ ! -f ${CONFIG_UTILS_FILE} ] && echo "File not found." && exit 1
. ${CONFIG_UTILS_FILE}
[ $? -ne 0 ] && echo "Fail." && exit 1 ; printResult ${RESULT_PASS}

# Make sure allof the required tools are installed.
echo -n "    Check for rpmdev-setuptree ... "
which rpmdev-setuptree &> ${LOG}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}
echo -n "    Check for rpmbuild ... "
which rpmbuild &> ${LOG}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

# CD to the build directory.
echo -n "    CD to build dir ... "
cd ${BLD_DIR} &> ${LOG}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

# Start with a clean rpmbuild directory.
echo -n "    Clean out the rpmbuild directory ... "
rm -rf ~/rpmbuild &> ${LOG}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

# Initialize the rpmbuild directory ... "
echo -n "    Initialize the rpmbuild directory ... "
rpmdev-setuptree &> ${LOG}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

# Build the NAS Proxy RPM.
echo -n "    Build the NAS Proxy RPM file ... "
rpmbuild -vv -ba NASProxy.spec &> ${LOG}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

printResult ${RESULT_PASS} "    Success.\n"
exit 0

