#!/bin/bash

################################################################################
# Backup the VMs that are stored on an ESXi server.
#
# You can specify the exact name of a single VM.  This will force the tool to
# backup that single VM instead of all VMs.
#
# This script makes some assumptions:
# 1. The name of a VM is the same as the name of the directory containing the VM.
# 2. The name of a VM is the same as the name of its .vmx file.
# 3. There are no spaces in the VM names.  The script doesn't like spaces.
#
# So, if you rename any of your VMs after you created them, this script will
# fail to back them up.
#
# The script will try to shrink the size of the VMDK files before backing them
# up.  If you want the script to do that for you, then you have to follow a
# few simple rules:
# 1. Each VM has to have the VMware Tools installed.  We have to get the IP
#    address of a VM in order to "ssh" into it and perform some tasks, and
#    VMware Tools is required for that to happen.
# 2. This function also requires "root" access to the VM, via "ssh".
################################################################################

readonly TOP_DIR=$( cd `dirname ${0}`/../.. && echo ${PWD} )

################################################################################
# As part of the task of trimming the size of the VMDK files, we need to zero
# the unused space on each device.  For example, we will try to use the dd
# tool to zero all of the unused space (i.e. "dd if=/dev/zero ...").
#
# Input:
#   VMID - The ID of the VM on the ESXi server.
#
#   OVA_NAME - The name of the VM.
#
# Output:
#   N/A
################################################################################
zeroVMDK() {
	local VMID=${1}
	local OVA_NAME=${2}

	local VM_IP_ADDR=""

	echo "  Attempt to zero the vmdk"

	# Get the IP address of the VM.  Note that your VM needs to run VMware
	# tools in order for this to work.
	echo -n "    Look for an IP Address ... "
	runESXiCmd "vim-cmd vmsvc/get.summary ${VMID} | grep ipAddress" &> ${LOG}
	[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1
	grep -q 'ipAddress = <unset>' ${LOG}
	if [ $? -eq 0 ]; then
		printResult ${RESULT_PASS} "None.\n"
	else
		VM_IP_ADDR=`grep "ipAddress = " ${LOG} | sed 's/^.*ipAddress = "//;' | sed 's/".*//;'`
		printResult ${RESULT_PASS} "Done (${VM_IP_ADDR}).\n"

		echo -n "    Check free space ... "
		ssh root@${VM_IP_ADDR} df -h /root &> ${LOG}
		if [ $? -ne 0 ]; then
			printResult ${RESULT_WARN} "Unsuccessful.  Moving on.\n"
		else
			VM_AVAIL_SPACE=`tail -1 ${LOG} | awk {'print $4'}`
			printResult ${RESULT_PASS} "Pass (${VM_AVAIL_SPACE} avail).\n"

			# Can't check the return code from this command.  If we
			# are successful, the command will fail.
			echo -n "    Zero fill ... "
			ssh root@${VM_IP_ADDR} dd if=/dev/zero of=/root/zero.bin bs=1M count=100G &> ${LOG}
			printResult ${RESULT_PASS} "Done.\n"

			echo -n "    Check free space ... "
			ssh root@${VM_IP_ADDR} df -h /root &> ${LOG}
			if [ $? -ne 0 ]; then
				printResult ${RESULT_WARN} "Unsuccessful.  Moving on.\n"
			else
				VM_AVAIL_SPACE=`tail -1 ${LOG} | awk {'print $4'}`
				printResult ${RESULT_PASS} "Pass (${VM_AVAIL_SPACE} avail).\n"

				echo -n "    Remove zero-fill file ... "
				ssh root@${VM_IP_ADDR} rm -f /root/zero.bin &> ${LOG}
				if [ $? -ne 0 ]; then
					printResult ${RESULT_WARN} "Unsuccessful.  Moving on.\n"
				else
					ssh root@${VM_IP_ADDR} df -h /root &> ${LOG}
					VM_AVAIL_SPACE=`tail -1 ${LOG} | awk {'print $4'}`
					printResult ${RESULT_PASS}
				fi
			fi
		fi
	fi
}

################################################################################
# Backup a single VM.
#
# Input:
#   VMID - The ID of the VM on the ESXi server.
#
#   OVA_NAME - The name of the VM.
#
# We make some big assumptions about the location of the VM based on the input
# values.  So the script might fail if you renamed your VM after you create it.
################################################################################
backupOneFile() {
	local VMID=${1}
	local OVA_NAME=${2}

	local OVA_FILE_NAME=${OVA_NAME}.ova
	local OVA_PATH_NAME_RMT=${ESXI_DATASTORE_DIR}/tmp.${OVA_FILE_NAME}
	local OVA_PATH_NAME_LCL=${BACKUP_DIR}/${OVA_FILE_NAME}

	local VMX_PATH_LOCL=/tmp/${OVA_NAME}.vmx

	# Delete the local copy of the OVA file.  We don't want to accidentally
	# use it if the backup fails.
	echo -n "  Delete local OVA file ... "
	rm -f ${OVA_PATH_NAME_LCL} &> ${LOG}
	[ $? -ne 0 ] && echo "Fail." && exit 1 ; printResult ${RESULT_PASS}

	# Download the vmx file, so we can edit it.
	echo "  Modify VM configuration"
	echo -n "    Download vmx file ... "
	runESXiSCPGet ${ESXI_DATASTORE_DIR}/${OVA_NAME}/${OVA_NAME}.vmx ${VMX_PATH_LOCL}
	[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1
	[ ! -f ${VMX_PATH_LOCL} ] && printResult ${RESULT_FAIL} "File missing." && exit 1
	printResult ${RESULT_PASS}

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

	# Check to see if the VM is powered on.
	echo -n "  Check for \"power on\" state ... "
	runESXiCmd "vim-cmd vmsvc/power.getstate ${VMID}" &> ${LOG}
	if [ $? -ne 0 ]; then
		printResult ${RESULT_WARN} "Unsuccessful.  Moving on.\n"
	else
		grep -q "Powered on" ${LOG}
		if [ $? -ne 0 ]; then
			printResult ${RESULT_WARN} "Not powered on.  Moving on.\n"
		else
			printResult ${RESULT_PASS}

			# Let's try to trim the VMDK files.  The first step is to
			# zero all of the unused space.
			zeroVMDK ${VMID} ${OVA_NAME}

			# We need to shut it down.  If we can't shut it down,
			# then we need to stop.
			echo -n "  Issuing \"Power Shutdown\" command ... "
			runESXiCmd "vim-cmd vmsvc/power.shutdown ${VMID}" &> ${LOG}
			if [ $? -ne 0 ]; then
				printResult ${RESULT_FAIL} && exit 1
			else
				printResult ${RESULT_PASS}
			fi
		fi

		echo -n "  Wait for VM to reach the \"power off\" state ... "
		while true; do
			runESXiCmd "vim-cmd vmsvc/power.getstate ${VMID}" &> ${LOG}
			if [ $? -ne 0 ]; then
				printResult ${RESULT_FAIL}
			else
				grep -q "Powered off" ${LOG}
				if [ $? -eq 0 ]; then
					printResult ${RESULT_PASS}
					break
				fi
			fi
		done
	fi

	echo -n "  Shrink vmdk file(s) ... "
	runESXiCmd "/bin/vmkfstools -K ${OVA_NAME}/${OVA_NAME}.vmdk" &> ${LOG}
	[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

	# Create an OVA file from the VM.  We specify SHA1 so that the OVA file
	# can be loaded by an ESXi 5 server.  ESXi 5 doesn't support SHA256.
	echo -n "  Create OVA file ... "
	runESXiCmd "${OVFTOOL} --noSSLVerify --overwrite --disableVerification --noSSLVerify --powerOffSource --shaAlgorithm=SHA1 -ds=datastore1 vi://${ESXI_USERNAME}:${ESXI_PASSWORD}@${ESXI_IP}/${OVA_NAME} ${OVA_PATH_NAME_RMT}" &> ${LOG}
	[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1
	grep -q "Completed successfully" ${LOG}
	[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

	# Take a look on the ESXi server and make sure the OVA file is there.
	echo -n "  Use 'ls' to look for ${OVA_NAME} ... "
	runESXiCmd "ls -ldh ${OVA_PATH_NAME_RMT}" &> ${LOG}
	[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1
	grep -q "No such file or directory" ${LOG}
	[ $? -eq 0 ] && printResult ${RESULT_FAIL} "Not found.\n" && exit 1
	OVA_FILE_SIZE=`grep ${OVA_PATH_NAME_RMT} ${LOG} | tail -1 | awk {'print $5'}`
	printResult ${RESULT_PASS} "Found (${OVA_FILE_SIZE} bytes).\n"

	# Download the OVA file from the ESXi server.
	echo -n "  Download OVA file ... "
	runESXiSCPGet ${OVA_PATH_NAME_RMT} ${OVA_PATH_NAME_LCL}
	[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

	# Delete the OVA file from the ESXi server.
	echo -n "  Delete remote OVA file ... "
	runESXiCmd "rm -f ${OVA_PATH_NAME_RMT}" &> ${LOG}
	[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

	echo ""
}

################################################################################
####   Processing starts here.
################################################################################

echo "Initialization"
echo -n "  CD to the top directory (${TOP_DIR}) ... "
cd ${TOP_DIR}
[ $? -ne 0 ] && echo "Fail." && exit 1 ; echo "Done."

readonly LOG=/tmp/`basename ${0}`.log
echo -n "  Initialize log file (${LOG}) ... "
rm -f ${LOG} &> /dev/null
[ $? -ne 0 ] && echo "Unable to delete old log file." && exit 1
touch ${LOG} &> /dev/null
[ $? -ne 0 ] && echo "Unable to create empty log file." && exit 1
echo "Pass."

# Load our Print utilities.
echo -n "  Loading Print utilities library ... "
readonly PRINT_UTILS_FILE=${TOP_DIR}/lib/printUtils
[ ! -f ${PRINT_UTILS_FILE} ] && echo "File not found." && exit 1
. ${PRINT_UTILS_FILE}
[ $? -ne 0 ] && echo "Fail." && exit 1 ; printResult ${RESULT_PASS}

# Load our build utilities.
echo -n "  Loading build utilities library ... "
readonly BUILD_UTILS_FILE=${TOP_DIR}/lib/buildUtils
[ ! -f ${BUILD_UTILS_FILE} ] && echo "File not found." && exit 1
. ${BUILD_UTILS_FILE}
[ $? -ne 0 ] && echo "Fail." && exit 1 ; printResult ${RESULT_PASS}

# Load our ESXi utilities.
echo -n "  Loading ESXi utilities library ... "
readonly ESXI_UTILS_FILE=${TOP_DIR}/lib/esxiUtils
[ ! -f ${ESXI_UTILS_FILE} ] && echo "File not found." && exit 1
. ${ESXI_UTILS_FILE}
[ $? -ne 0 ] && echo "Fail." && exit 1 ; printResult ${RESULT_PASS}

echo "  Initialize build Utils"
buildUtilsInit 4

# Load our build conf file.
echo "  Load the build configuration"
loadBuildConfigFile 4

# Load the backup/restore config file, if it exists.  If it doesn't exist,
# create it and query for the information.
readonly BKUP_CFG_FILE=${TOP_DIR}/.bkuprc
if [ -f ${BKUP_CFG_FILE} ]; then
	. ${BKUP_CFG_FILE}
fi
while true; do
	read    -p "    Backup destination dir: [${BACKUP_DIR}] "
	[ ! -z "${REPLY}" ] && BACKUP_DIR=${REPLY}

	[ -z "${BACKUP_DIR}" ] && echo "Please enter the name of the backup directory." && continue

	[ ! -d ${BACKUP_DIR} ] && echo ">${BACKUP_DIR}< is not the name of a directory." && continue

	echo "export BACKUP_DIR=${BACKUP_DIR}" > ${BKUP_CFG_FILE}
	[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1
	break
done
readonly BACKUP_DIR

echo ""

# Show the user what we're going to do, and let them decide if they want to
# proceed.
echo "Here's the plan:"
echo "  Backing up from server:  ${ESXI_IP}"
if [ $# -gt 0 ]; then
	echo "  Backing up a single VM:  ${1}"
fi
echo "  Backing up to directory: ${BACKUP_DIR}"
read -p "Press <ENTER> to continue, <CTRL-C> to quit "
echo ""

# Can we access the server?
echo -n "Attempt to access the server ... "
ping -c 2 ${ESXI_IP} &> /dev/null
[ $? -ne 0 ] && echo "Fail." && exit 1 ; echo "Done."

# Get the list of VMs into our log file.
echo -n "Get the list of VMIDs and VM Names ... "
runESXiCmd "vim-cmd vmsvc/getallvms" &> ${LOG}
[ $? -ne 0 ] && echo "Fail." && exit 1

# Trim off the junk at the beginning of the file.
FIRST_LINE=`grep -n "Vmid *Name *File" ${LOG} | sed "s/:/ /" | awk {'print $1'}`
sed -i "1,${FIRST_LINE}d" ${LOG}

# The last line is the prompt after the ovftool commmand.  Get rid of it.
LAST_LINE=`grep -n "~" ${LOG} | sed "s/:/ /;" | awk {'print $1'}`
sed -i "${LAST_LINE}d" ${LOG}

TOTAL_VMS=`cat ${LOG} | wc -l`
echo "Done (${TOTAL_VMS} VMs)." ; echo ""

COUNTER=0
OLD_IFS="${IFS}"
IFS="
"
for LINE in `cat ${LOG}`; do
	COUNTER=$(( COUNTER + 1 ))

	ID=`echo ${LINE} | awk {'print $1'}`
	NAME=`echo ${LINE} | awk {'print $2'}`

	# If the user specified the name of a particular VM on the command line,
	# then only backup that single VM.  Skip all the rest.
	if [ $# -gt 0 ]; then
		[ "${1}" != "${NAME}" ] && continue
		echo "1/1: `date` : Backing up ${NAME} : VMID is ${ID}"
	else
		echo "${COUNTER}/${TOTAL_VMS}: `date` : Backing up ${NAME} : VMID is ${ID}"
	fi

	backupOneFile "${ID}" "${NAME}"
done
IFS=${OLD_IFS}

########################################
# Done.  Success.
printResult ${RESULT_PASS} "`basename ${0}` Success.\n"
exit 0

