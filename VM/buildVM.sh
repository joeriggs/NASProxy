#!/bin/bash

################################################################################
# Build the NAS Proxy (or optionally build the NAS Encryptor) OVA file.
#
# If the variable NAS_ENCRYPTOR_RPM_FILE is defined, it points to an RPM file
# that contains the NAS Encryptor files.  If that's the case, then include the
# file in the OVA file.  So we will have a "NAS Encryptor" instead of a plain
# old "NAS Proxy".
#
# You need to enable SSH on the ESXi server before you run this script.
#
# You also need to install ovftool on the ESXi server:
# 1. Download and install ovftool onto a Linux box.  I've been running with:
#      VMware ovftool 4.2.0 (build-5965791)
# 2. scp the /usr/lib/vmware-ovftool directory to /vmfs/volumes/datastore1 on
#    the ESXi server.  This tool expects to find ovftool in that location.
# 3. Edit the vmware-ovftool/ovftool script and change the shell interpreter
#    from /bin/bash to /bin/sh.
# 4. Test it and make sure it works.
################################################################################

readonly BLD_DIR=$( cd `dirname ${0}`    && echo ${PWD} )
readonly TOP_DIR=$( cd ${BLD_DIR}/..     && echo ${PWD} )
readonly RPM_DIR=${TOP_DIR}/RPM

########################################
echo "Building the VM image:"
echo "  Initialization:"

echo -n "    CD to the build directory (${BLD_DIR}) ... "
cd ${BLD_DIR}
[ $? -ne 0 ] && echo "Fail." && exit 1 ; echo "Done."

readonly LOG=/tmp/`basename ${0}`.log
echo -n "    Initialize log file (${LOG}) ... "
rm -f ${LOG} &> /dev/null
[ $? -ne 0 ] && echo "Unable to delete old log file." && exit 1
touch ${LOG} &> /dev/null
[ $? -ne 0 ] && echo "Unable to create empty log file." && exit 1
echo "Pass."

# Load our Print utilities.
echo -n "    Loading Print utilities library ... "
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

# Load our ESXi utilities.
echo -n "    Loading ESXi utilities library ... "
readonly ESXI_UTILS_FILE=${TOP_DIR}/lib/esxiUtils
[ ! -f ${ESXI_UTILS_FILE} ] && echo "File not found." && exit 1
. ${ESXI_UTILS_FILE}
[ $? -ne 0 ] && echo "Fail." && exit 1 ; printResult ${RESULT_PASS}

# Load our build conf file.
loadBuildConfigFile

# Check for some required packages.
installYUMPackage "expect"
installYUMPackage "yum-utils"
installYUMPackage "genisoimage"
installYUMPackage "wget"

# Make sure the ovftool is installed.  We will need it.
verifyOvftool

readonly ISO_REPO_SITE=http://mirror.arizona.edu/centos/8.1.1911/isos/x86_64
readonly ISO_FILE_NAME=CentOS-8.1.1911-x86_64-dvd1.iso
readonly ISO_CSUM_NAME=CHECKSUM

readonly OVA_NAME=NASProxy
readonly OVA_FILE_NAME=${OVA_NAME}.ova
readonly OVA_PATH_NAME_RMT=${ESXI_DATASTORE_DIR}/tmp.${OVA_FILE_NAME}
readonly OVA_PATH_NAME_LCL=${TOP_DIR}/${OVA_FILE_NAME}

readonly ESXI_PROJECT_DIR=${ESXI_DATASTORE_DIR}/${OVA_NAME}

readonly VMX_PATH_LOCL=/tmp/${OVA_NAME}.vmx

# Delete the local copy of the OVA file.  We don't want to accidentally grab it
# if the build fails.
echo -n "    Delete local OVA file ... "
rm -f ${OVA_PATH_NAME_LCL} &> ${LOG}
[ $? -ne 0 ] && echo "Fail." && exit 1 ; printResult ${RESULT_PASS}

echo ""

########################################
# If there is already a VM on the ESXi server, shut it down and delete it now.
deleteOldVM

echo ""

########################################
# Upload the OS distribution ISO to ESXi server.
echo "  OS Distro ISO Processing:"

# Check to see if the ISO file is already on the server.  Skip ahead if it is.
echo -n "    Look for ISO file on ESXi server ... "
runESXiCmd "ls /vmfs/volumes/datastore1/${ISO_FILE_NAME}" &> ${LOG}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1

grep -q "No such file or directory" ${LOG}
if [ $? -ne 0 ]; then
	printResult ${RESULT_PASS} "Found.\n"
else
	printResult ${RESULT_WARN} "Missing.\n"

	# Download the ISO.
	# Check to see if the ISO file and checksum file have been downloaded.
	# If not, then download them now.
	echo -n "    Check for ISO file (${ISO_FILE_NAME}) ... "
	if [ -f ${ISO_FILE_NAME} ]; then
		printResult ${RESULT_PASS} "Found.\n"
	else
		printResult ${RESULT_WARN} "Missing.\n"

		echo -n "      Download ... "
		wget ${ISO_REPO_SITE}/${ISO_FILE_NAME} &> ${LOG}
		[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}
	fi

	echo -n "    Check for checksum file ... "
	if [ -f ${ISO_CSUM_NAME} ]; then
		echo "Found."
	else
		printResult ${RESULT_WARN} "Missing.\n"

		echo -n "      Download ... "
		wget ${ISO_REPO_SITE}/${ISO_CSUM_NAME} &> ${LOG}
		[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}
	fi

	# Verify the ISO was downloaded cleanly.
	echo -n "    Calculate SHA256 checksum ... "
	sha256sum ${ISO_FILE_NAME} > /tmp/j1
	[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1
	CALC_CHECKSUM=`cat /tmp/j1 | awk {'print $1'}`
	echo "Pass (${CALC_CHECKSUM})."

	echo -n "    Locate checksum in checksum file ... "
	REAL_CHECKSUM=`grep ${ISO_FILE_NAME} ${ISO_CSUM_NAME} | grep SHA256 | awk {'print $4'}`
	[ -z "${REAL_CHECKSUM}" ] && printResult ${RESULT_FAIL} && exit 1
	echo "Pass (${REAL_CHECKSUM})."

	echo -n "    Compare checksum values ... "
	[ "${CALC_CHECKSUM}" != "${REAL_CHECKSUM}" ] && printResult ${RESULT_FAIL} && exit 1
	printResult ${RESULT_PASS}

	echo -n "    Upload ISO file to ESXi server ... "
	runESXiSCPPut ${ISO_FILE_NAME} /vmfs/volumes/datastore1
	[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}
fi

echo ""

########################################
# Upload the kickstart ISO to ESXi server.
echo "  Kickstart ISO Processing:"

readonly KICKSTART_ISO_NAME=kickstart.iso
readonly KICKSTART_ISO_PATH=/vmfs/volumes/datastore1/${KICKSTART_ISO_NAME}

echo -n "    Check for ${KICKSTART_ISO_NAME} on the ESXi server ... "
runESXiCmd "ls -l ${KICKSTART_ISO_PATH}" &> ${LOG}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1

grep -q "No such file or directory" ${LOG}
if [ $? -ne 0 ]; then
	printResult ${RESULT_WARN} "Found.\n"

	echo -n "      Deleting old file ... "
	runESXiCmd "rm -f ${KICKSTART_ISO_PATH}" &> ${LOG}
	[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1
	grep -q "Device or resource busy" ${LOG}
	[ $? -eq 0 ] && printResult ${RESULT_FAIL} "File busy.  Can't delete.\n" && exit 1
	printResult ${RESULT_PASS}

	echo -n "    Check again ... "
	runESXiCmd "ls -l ${KICKSTART_ISO_PATH}" &> ${LOG}
	[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1

	grep -q "No such file or directory" ${LOG}
	[ $? -ne 0 ] && printResult ${RESULT_FAIL} "File still there.\n" && exit 1

	printResult ${RESULT_PASS}
else
	printResult ${RESULT_PASS} "Not found.\n"
fi

##########
# NAS Proxy RPM file processing.  The RPM file is already built.  We just need
# to put it in a tar file (due to ISO 9660 filename conventions) and move the
# tar file to the kickstart directory.
echo    "    NAS Proxy RPM file:"
echo -n "      CD to RPM dir ... "
pushd ${RPM_DIR} &> /dev/null
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

echo -n "      Get list of new RPM file(s) ... "
find . -maxdepth 1 -name "*.rpm" &> ${LOG}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

echo -n "      Count the RPM files ... "
NUM_RPM_FILES=`wc -l ${LOG} | awk {'print $1'}`
[ ${NUM_RPM_FILES} -ne 1 ] && printResult ${RESULT_FAIL} "Fail (${NUM_RPM_FILES}).\n" && exit 1 ; printResult ${RESULT_PASS} "Pass (${NUM_RPM_FILES}).\n"

echo -n "      Get RPM file name ... "
RPM_FILE_NAME=`cat ${LOG}` &> /dev/null
[ -z "${RPM_FILE_NAME}" ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS} "Pass (${RPM_FILE_NAME}).\n"

echo -n "      Create tar file with RPM file ... "
TAR_FILE_NAME=nasproxy.tar
TAR_FILE=${PWD}/${TAR_FILE_NAME}
tar cf ${TAR_FILE} ${RPM_FILE_NAME} &> ${LOG}
[ -z "${RPM_FILE_NAME}" ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS} "Pass (${RPM_FILE_NAME}).\n"

echo -n "      CD back to VM dir ... "
popd &> /dev/null
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

echo -n "      Remove old tar files from kickstart dir ... "
rm -f ks/*.tar &> ${LOG}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

echo -n "      Move NASProxy tar file to kickstart directory ... "
mv -f ${TAR_FILE} ks &> ${LOG}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

echo ""

##########
# (Optional) NAS Encryptor RPM file processing.
# If the variable NAS_ENCRYPTOR_RPM_FILE is defined, include it in the kickstart
# ISO.
if [ ! -z "${NAS_ENCRYPTOR_RPM_FILE}" ]; then
	if [ -f "${NAS_ENCRYPTOR_RPM_FILE}" ]; then
		echo    "    NAS Encryptor RPM file:"
		echo -n "      Copy file to local dir ... "
		readonly NAS_ENCRYPTOR_RPM_FILE_NAME="./`basename ${NAS_ENCRYPTOR_RPM_FILE}`"
		cp -f ${NAS_ENCRYPTOR_RPM_FILE} ${NAS_ENCRYPTOR_RPM_FILE_NAME} &> /dev/null
		[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS} "Pass (${NAS_ENCRYPTOR_RPM_FILE_NAME}).\n"

		echo -n "      Create tar file with RPM file ... "
		TAR_FILE_NAME=nasenc.tar
		TAR_FILE=${PWD}/${TAR_FILE_NAME}
		tar cf ${TAR_FILE} ${NAS_ENCRYPTOR_RPM_FILE_NAME} &> ${LOG}
		[ -z "${TAR_FILE}" ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

		echo -n "      Delete local RPM file ... "
		rm -f ${NAS_ENCRYPTOR_RPM_FILE_NAME} &> /dev/null
		[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

		echo -n "      Move NASEncryptor tar file to kickstart directory ... "
		mv -f ${TAR_FILE} ks &> ${LOG}
		[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}
	else
		printResult ${RESULT_FAIL} "NAS Encryptor file (${NAS_ENCRYPTOR_RPM_FILE}) missing.\n" && exit 1
	fi
else
	echo -n "    NAS Encryptor RPM file processing ... "
	printResult ${RESULT_WARN} "Skipping.\n"
fi

##########
# Create the kickstart ISO file.
echo -n "    Create ${KICKSTART_ISO_NAME} ... "
mkisofs -V OEMDRV -o ${KICKSTART_ISO_NAME} ks &> ${LOG}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

echo -n "    Upload ${KICKSTART_ISO_NAME} to the ESXi server ... "
runESXiSCPPut ${KICKSTART_ISO_NAME} ${KICKSTART_ISO_PATH}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

echo -n "    Verify ... "
runESXiCmd "ls -l ${KICKSTART_ISO_PATH}" &> ${LOG}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1
grep -q "No such file or directory" ${LOG}
[ $? -eq 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

echo -n "    Delete local copy ... "
rm -f ${KICKSTART_ISO_NAME} &> ${LOG}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

echo -n "    Delete NASProxy tar file ... "
rm -f ks/${TAR_FILE_NAME} &> ${LOG}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

echo ""

########################################
# Create the VM.  This command returns the vmid.
echo    "  Create the VM:"

echo -n "    Create dummy VM ... "
runESXiCmd "vim-cmd vmsvc/createdummyvm ${OVA_NAME} \[datastore1\]" &> ${LOG}
printResult ${RESULT_PASS}

echo -n "    Look for VMID ... "
runESXiCmd "vim-cmd vmsvc/getallvms" &> ${LOG}

VMID=`grep ${OVA_NAME}/${OVA_NAME}.vmx ${LOG} | awk {'print $1'}`
[ -z "${VMID}" ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS} "Pass (${VMID}).\n"

echo ""

########################################
# The VM is created.  Configure it.
echo    "  Configure the VM:"

# Set the disk size.
echo -n "    Set disk size ... "
runESXiCmd "vmkfstools -X 20GB /vmfs/volumes/datastore1/${OVA_NAME}/${OVA_NAME}.vmdk" &> ${LOG}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

# Add a network adapter.
# NOTE: I think this command is broken.  It creates the NIC, but it doesn't add it to the
#       "VM Network".  So it never works.  Therefore, we will add it manually.  That's not
#       ideal, but it'll do for now.
#echo -n "  Add network adapter ... "
#runESXiCmd "vim-cmd vmsvc/devices.createnic ${VMID} 0 vmxnet3 \\\"VM Network\\\"" &> ${LOG}
#[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1
#grep -q "vim.Network.Summary" ${LOG}
#[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

echo ""

########################################
# Download the vmx file, modify it, and upload it back to the ESXi server.
echo    "  Modify the vmx file:"

# Download the vmx file, so we can edit it.
echo -n "    Download ... "
runESXiSCPGet ${ESXI_DATASTORE_DIR}/${OVA_NAME}/${OVA_NAME}.vmx ${VMX_PATH_LOCL}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

# Change the "virtualHW version".  The CLI creates a V10 thingie, and the GUI
# won't allow us to edit it.  So changing the HW version to 8 fixes that.
echo -n "    Set virtualHW.version ... "
sed -i -e 's/virtualHW.version = "10"/virtualHW.version = "8"/;' ${VMX_PATH_LOCL}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

# Set Virtual DVD 0 to point to the OS Distribution ISO.
echo -n "    Configure DVD 0 for the OS Distro ISO ... "
echo "ide0:0.deviceType = \"cdrom-image\""                             >> ${VMX_PATH_LOCL}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} "Fail1.\n" && exit 1
echo "ide0:0.fileName = \"/vmfs/volumes/datastore1/${ISO_FILE_NAME}\"" >> ${VMX_PATH_LOCL}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} "Fail2.\n" && exit 1
echo "ide0:0.present = \"TRUE\""                                       >> ${VMX_PATH_LOCL}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} "Fail3.\n" && exit 1
printResult ${RESULT_PASS}

# Set Virtual DVD 1 to point to the kickstart ISO.
echo -n "    Configure DVD 1 for the Kickstart ISO ... "
echo "ide1:0.deviceType = \"cdrom-image\""                             >> ${VMX_PATH_LOCL}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} "Fail1.\n" && exit 1
echo "ide1:0.fileName = \"${KICKSTART_ISO_PATH}\""                     >> ${VMX_PATH_LOCL}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} "Fail2.\n" && exit 1
echo "ide1:0.present = \"TRUE\""                                       >> ${VMX_PATH_LOCL}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} "Fail3.\n" && exit 1
printResult ${RESULT_PASS}

# Set the memory size.
echo -n "    Configure memory size ... "
echo 'memSize = "2048"'                                                >> ${VMX_PATH_LOCL}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1
printResult ${RESULT_PASS}

# Add the network adapter.  There is a vim-cmd command to do this task (see the
# code above), but it seems to be broken.  So we'll manually add it for now.
echo -n "    Add network adapter ... "
echo 'ethernet0.virtualDev = "vmxnet3"'                                >> ${VMX_PATH_LOCL}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} "Fail1.\n" && exit 1
echo 'ethernet0.networkName = "VM Network"'                            >> ${VMX_PATH_LOCL}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} "Fail2.\n" && exit 1
echo 'ethernet0.addressType = "generated"'                             >> ${VMX_PATH_LOCL}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} "Fail3.\n" && exit 1
echo 'ethernet0.present = "TRUE"'                                      >> ${VMX_PATH_LOCL}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} "Fail4.\n" && exit 1
printResult ${RESULT_PASS}

# Upload the modified vmx file.
echo -n "    Upload ... "
runESXiSCPPut ${VMX_PATH_LOCL} ${ESXI_DATASTORE_DIR}/${OVA_NAME}/${OVA_NAME}.vmx
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

# Reload the VM, so it accepts all of our changes.
echo -n "    Reload the VM ... "
runESXiCmd "vim-cmd vmsvc/reload ${VMID}" &> ${LOG}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

echo ""

########################################
# Start the VM and let it configure itself.
echo    "  Boot the VM.  Let it configure itself:"
echo -n "    Issuing \"Power On\" command ... "
runESXiCmd "vim-cmd vmsvc/power.on ${VMID}" &> ${LOG}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

# First, we wait to see it get powered on.
echo -n "    Wait for \"power on\" state ... "
while true; do
	runESXiCmd "vim-cmd vmsvc/power.getstate ${VMID}" &> ${LOG}
	[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1
	grep -q "Powered on" ${LOG}
	[ $? -eq 0 ] && printResult ${RESULT_PASS} && break
	sleep 1
done

# Then we wait for it to complete the installation and shut itself off.
echo -n "    Wait for \"power off\" state (this will take several minutes) ... "
while true; do
	runESXiCmd "vim-cmd vmsvc/power.getstate ${VMID}" &> ${LOG}
	[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1
	grep -q "Powered off" ${LOG}
	[ $? -eq 0 ] && printResult ${RESULT_PASS} && break
	sleep 1
done

echo ""

########################################
# Post processing.  The VM is created.  Now we need to clean it up and save it.
# Download the vmx file, modify it, and upload it back to the ESXi server.
echo    "  Post processing:"

# Download the vmx file, so we can edit it.
echo -n "    Download vmx file ... "
runESXiSCPGet ${ESXI_DATASTORE_DIR}/${OVA_NAME}/${OVA_NAME}.vmx ${VMX_PATH_LOCL}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

# Remove DVD 0 (the OS Distro ISO).
echo -n "    Remove DVD 0 ... "
sed -i '/^ide0:0/d' ${VMX_PATH_LOCL}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

# Remove DVD 1 (the Kickstart ISO).
echo -n "    Remove DVD 1 ... "
sed -i '/^ide1:0/d' ${VMX_PATH_LOCL}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

# Upload the modified vmx file.
echo -n "    Upload ... "
runESXiSCPPut ${VMX_PATH_LOCL} ${ESXI_DATASTORE_DIR}/${OVA_NAME}/${OVA_NAME}.vmx
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

# Reload the VM, so it accepts all of our changes.
echo -n "    Reload the VM ... "
runESXiCmd "vim-cmd vmsvc/reload ${VMID}" &> ${LOG}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

echo ""

########################################
# Create an OVA file from the VM.  We specify SHA1 so that the OVA file can be
# loaded by an ESXi 5 server.  ESXi 5 doesn't support SHA256.
echo -n "  Create OVA file ... "
runESXiCmd "${OVFTOOL} --noSSLVerify --overwrite --disableVerification --noSSLVerify --powerOffSource --shaAlgorithm=SHA1 -ds=datastore1 vi://${ESXI_USERNAME}:${ESXI_PASSWORD}@${ESXI_IP}/${OVA_NAME} ${OVA_PATH_NAME_RMT}" &> ${LOG}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1
grep -q "Completed successfully" ${LOG}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

# Take a look at the ESXi server and make sure the OVA file is there.
echo -n "  Use 'ls' to look for ${OVA_NAME} ... "
runESXiCmd "ls -ld ${OVA_PATH_NAME_RMT}" &> ${LOG}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1
grep -q "No such file or directory" ${LOG}
[ $? -eq 0 ] && printResult ${RESULT_FAIL} "Not found.\n" && exit 1 ; printResult ${RESULT_PASS} "Found.\n"

# Download the OVA file from the ESXi server.
echo -n "    Download OVA file ... "
runESXiSCPGet ${OVA_PATH_NAME_RMT} ${OVA_PATH_NAME_LCL}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

# Delete the OVA file on the ESXi server.
echo -n "    Delete remote OVA file ... "
runESXiCmd "rm -f ${OVA_PATH_NAME_RMT}" &> ${LOG}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

# Delete the kickstart file on the ESXi server.
echo -n "    Delete remote kickstart file ... "
runESXiCmd "rm -f ${KICKSTART_ISO_PATH}" &> ${LOG}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

echo -n "    Clean up local kickstart directory ... "
rm -f ks/*.tar &> ${LOG}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

# Delete the VM from the ESXi server.
deleteOldVM

echo ""

########################################
# Done.  Success.
printResult ${RESULT_PASS} "  `basename ${0}` Success.\n"
exit 0

