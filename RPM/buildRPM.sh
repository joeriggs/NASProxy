#!/bin/bash

################################################################################
# Build the RPM file that represents the current release of the NAS Proxy.
################################################################################

readonly BLD_DIR=$( cd `dirname ${0}`    && echo ${PWD} )
readonly TOP_DIR=$( cd ${BLD_DIR}/..     && echo ${PWD} )
export TOP_DIR

echo "Building the NAS Proxy RPM file:"

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

# Load our Operating System Version library.
echo -n "    Loading Operating System Version library ... "
readonly OS_VERSION_FILE=${TOP_DIR}/lib/osVersion
[ ! -f ${OS_VERSION_FILE} ] && echo "File not found." && exit 1
. ${OS_VERSION_FILE}
[ $? -ne 0 ] && echo "Fail." && exit 1 ; printResult ${RESULT_PASS}

buildUtilsInit 4
osVersionInit ${LOG} 1 4

# Check for some required packages.
[ ${LOCAL_OS_IS_RHEL} -eq 1 ] && [ ${RHEL_MAJOR_VERSION} -eq 7 ] && installYUMPackage "rpm-build"
installYUMPackage "rpmdevtools"

echo ""

########################################
# Build the RPM.
echo "  Build the RPM:"

# CD to the build directory.
echo -n "    CD to build dir ... "
cd ${BLD_DIR} &> ${LOG}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

# Delete any existing RPM files.
echo -n "    Delete old RPM files ... "
rm -f *.rpm &> ${LOG}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

# Build the RPM right here!
readonly RPMBUILD_DIR=${BLD_DIR}/rpmbuild
echo -n "    Set rpmbuild dir to the current dir ... "
echo "%_topdir ${RPMBUILD_DIR}" > ~/.rpmmacros
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

# Start with a clean rpmbuild directory.
echo -n "    Clean out the rpmbuild directory ... "
rm -rf ${RPMBUILD_DIR} &> ${LOG}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

# Initialize the rpmbuild directory ... "
echo -n "    Initialize the rpmbuild directory ... "
rpmdev-setuptree &> ${LOG}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

# Build the NAS Proxy RPM.
echo -n "    Build the NAS Proxy RPM file ... "
rpmbuild -vv -ba NASProxy.spec &> ${LOG}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

# Move the RPM file out of the rpmbuild area.
echo -n "    Extract RPM file ... "
mv ${RPMBUILD_DIR}/RPMS/x86_64/*.rpm . &> ${LOG}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

# Delete the rpmbuild directory.
echo -n "    Delete the rpmbuild directory ... "
rm -rf ${RPMBUILD_DIR} &> ${LOG}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

echo ""

########################################
printResult ${RESULT_PASS} "  `basename ${0}` Success.\n"
exit 0

