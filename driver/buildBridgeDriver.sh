#!/bin/bash

################################################################################
# Build the Proxy Bridge driver on the local computer.
################################################################################

DRIVER_NAME=proxy_bridge

readonly BLD_DIR=$( cd `dirname ${0}`    && echo ${PWD} )
readonly TOP_DIR=$( cd ${BLD_DIR}/..     && echo ${PWD} )

readonly FUSE_RELEASE=fuse-3.9.2
readonly FUSE_RELEASE_FILE=${FUSE_RELEASE}.tar.xz
readonly FUSE_URL=https://github.com/libfuse/libfuse/releases/download/${FUSE_RELEASE}/${FUSE_RELEASE_FILE}
readonly FUSE_ARCHIVE=./fuse-3.9.2/build/lib/libfuse3.a

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

# Load our Operating System Version library.
echo -n "    Loading Operating System Version library ... "
readonly OS_VERSION_FILE=${TOP_DIR}/lib/osVersion
[ ! -f ${OS_VERSION_FILE} ] && echo "File not found." && exit 1
. ${OS_VERSION_FILE}
[ $? -ne 0 ] && echo "Fail." && exit 1 ; printResult ${RESULT_PASS}

buildUtilsInit 4
osVersionInit ${LOG} 1 4

# Check for some required packages.
[ ${LOCAL_OS_IS_RHEL} -eq 1 ] && [ ${RHEL_MAJOR_VERSION} -eq 7 ] && installYUMPackage "epel-release"
installYUMPackage "gcc"
installYUMPackage "libattr-devel"
installYUMPackage "openssl-devel"
installYUMPackage "zlib-devel"
installYUMPackage "wget"
installYUMPackage "meson"
installYUMPackage "ninja-build"

# CD to the build directory.
echo -n "    CD to build dir ... "
cd ${BLD_DIR} &> ${LOG}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

echo ""

########################################
# Build libfuse3.a.
echo "  libfuse:"
echo -n "    Is it already built? "
if [ -f ${FUSE_ARCHIVE} ]; then
	printResult ${RESULT_PASS} "Yes.\n"
else
	printResult ${RESULT_WARN} "No.\n"

	echo -n "    Checking for source archive ... "
	if [ ! -f ${FUSE_RELEASE_FILE} ]; then 
		printResult ${RESULT_WARN} "Missing.\n"
		echo -n "      Downloading source archive ... "
		wget -O ${FUSE_RELEASE_FILE} ${FUSE_URL} &> ${LOG}
		[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1
	fi
	printResult ${RESULT_PASS}

	echo -n "    Checking for source directory ... "
	if [ ! -d ${FUSE_RELEASE} ]; then
		printResult ${RESULT_WARN} "Missing.\n"
		echo -n "      Opening FUSE image ... "
		tar xvf ${FUSE_RELEASE_FILE} &> ${LOG}
		[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1
		[ ! -d ${FUSE_RELEASE} ] && printResult ${RESULT_FAIL} "Unable to find fuse source code.\n" && exit 1
	fi
	printResult ${RESULT_PASS}

	echo -n "    Pushd to build directory ... "
	pushd ${FUSE_RELEASE} &> ${LOG}
	[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

	echo -n "    Make build dir ... "
	mkdir -p build
	[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

	echo -n "    CD to build dir ... "
	cd build
	[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

	echo -n "    Clean old build ... "
	rm -rf * &> ${LOG}
	[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

	echo -n "    Run meson the first time ... "
	meson .. &> ${LOG}
	[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

	# Ignore this build.  For some reason, "meson configure" seems to work better
	# after we've done a build.  So do a throwaway build.
	echo -n "    Throw away first build ... "
	ninja-build &> ${LOG}
	printResult ${RESULT_PASS}

	echo -n "    Skip the \"examples\" build ... "
	meson configure -Dexamples=false &> ${LOG}
	[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

	echo -n "    Build the static library ... "
	meson configure --default-library both . &> ${LOG}
	[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

	echo -n "    Build libfuse ... "
	ninja-build &> ${LOG}
	[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

	echo -n "    Install libfuse (as root) ... "
	sudo ninja-build install &> ${LOG}
	[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

	echo -n "    Popd from build directory ... "
	popd &> ${LOG}
	[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

	# Check again to see if it's built.
	echo -n "    Make sure it's built ... "
	if [ -f ${FUSE_ARCHIVE} ]; then
		printResult ${RESULT_PASS} "Yes.\n"
	else
		printResult ${RESULT_FAIL} && exit 1
	fi
fi

echo ""

########################################
# Go build it.
echo "  Build driver:"

readonly SWITCHES="-D_REENTRANT -Wall -W -Wno-sign-compare -Wmissing-declarations -Wwrite-strings -DFE_OPTIMIZE_HEADER -DKEY_SET_PER_FILE -DDEBUG -DOVERLAY_MOUNT -Wno-unused -I . -I /usr/local/include -g -O0 -fno-strict-aliasing -MD -MP -c"

echo -n "    Compiling ... "
gcc ${SWITCHES} -D_FILE_OFFSET_BITS=64 -MT ${DRIVER_NAME}.o -o ${DRIVER_NAME}.o ${DRIVER_NAME}.c &>> ${LOG}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

echo -n "    Linking ... "
gcc -o${DRIVER_NAME} ${DRIVER_NAME}.o ${FUSE_ARCHIVE} -lcrypto -lz -lc -lpthread -lrt -ldl &>> ${LOG}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

echo -n "    Cleanup ... "
rm -f libfuse3.so* ${DRIVER_NAME}.d ${DRIVER_NAME}.o &> /dev/null
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

echo ""
printResult ${RESULT_PASS} "  `basename ${0}` Success.\n"
exit 0

