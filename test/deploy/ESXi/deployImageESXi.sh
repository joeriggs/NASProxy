#!/bin/bash

################################################################################
# Copy and deploy the specified OVA file on the ESXi server.
#
# Usage:
#   deployVM.sh [OVA_FILE_PATH] [VM_NAME]
#
#   OVA_FILE_PATH is the path to the file.  There is a default value.
#
#   VM_NAME is the name to give the VM on the ESXi server.  There is a default
#   name.e
################################################################################

readonly RUN_DIR=$( cd `dirname ${0}`    && echo ${PWD} )
readonly TOP_DIR=$( cd ${RUN_DIR}/..     && echo ${PWD} )

# Default values for the OVA file and VM name.
VM_NAME=NASProxy
OVA_FILE_NAME=${TOP_DIR}/${VM_NAME}.ova

[ ! -z "${1}" ] && OVA_FILE_NAME=${1}
readonly OVA_FILE_NAME

if [ ! -z "${2}" ]; then
	VM_NAME=${2}
else
	filename=`basename ${OVA_FILE_NAME}`
	VM_NAME=${filename%.*}
	unset filename
fi

readonly OVA_FILE_NAME VM_NAME
echo "OVA file is > ${OVA_FILE_NAME} <."
echo "VM name is > ${VM_NAME} <."
echo ""

########################################
echo "Deploy an OVA file:"

echo -n "  CD to the run directory (${RUN_DIR}) ... "
cd ${RUN_DIR}
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

# Load our ESXi utilities.
echo -n "  Loading ESXi utilities library ... "
readonly ESXI_UTILS_FILE=${TOP_DIR}/lib/esxiUtils
[ ! -f ${ESXI_UTILS_FILE} ] && echo "File not found." && exit 1
. ${ESXI_UTILS_FILE}
[ $? -ne 0 ] && echo "Fail." && exit 1 ; printResult ${RESULT_PASS}

# Load our build utilities.
echo -n "  Loading build utilities library ... "
readonly CONFIG_UTILS_FILE=${TOP_DIR}/lib/buildUtils
[ ! -f ${CONFIG_UTILS_FILE} ] && echo "File not found." && exit 1
. ${CONFIG_UTILS_FILE}
[ $? -ne 0 ] && echo "Fail." && exit 1 ; printResult ${RESULT_PASS}

# Load our build conf file.
loadBuildConfigFile
echo ""

readonly ESXI_PROJECT_DIR=${ESXI_DATASTORE_DIR}/${VM_NAME}
readonly RMT_OVA_NAME=${ESXI_DATASTORE_DIR}/`basename ${OVA_FILE_NAME}`

# If there is already a VM with ths requested name, stop now.
echo    "Make sure the VM name is unique:"
echo -n "  Get list of VMs ... "
runESXiCmd "vim-cmd vmsvc/getallvms" &> ${LOG}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

echo -n "  Look for VM ${VM_NAME} ... "
OLD_VMID=`grep ${VM_NAME} ${LOG} | awk {'print $1'}`
[ ! -z "${OLD_VMID}" ] && printResult ${RESULT_FAIL} "Fail (${OLD_VMID}).\n" && exit 1 ; printResult ${RESULT_PASS}
unset OLD_VMID

echo ""

########################################
# Verify the local copy of the OVA file exists.
echo -n "Verify ${OVA_FILE_NAME} exists ... "
[ ! -f ${OVA_FILE_NAME} ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

# Make sure the ovftool is installed.  We will need it.
verifyOvftool

echo ""

########################################
# Delete the old OVA file from the ESXi server.
echo -n "Delete old OVA file from ESXi server ... "
runESXiCmd "rm -f ${RMT_OVA_NAME}" &> ${LOG}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

echo -n "  Verify file is deleted ... "
runESXiCmd "ls -l ${RMT_OVA_NAME}" &> ${LOG}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1
grep -q "No such file or directory" ${LOG}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

echo ""

########################################
echo -n "Upload file ... "
runESXiSCPPut ${OVA_FILE_NAME} ${RMT_OVA_NAME}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

echo -n "  Verify upload ... "
runESXiCmd "ls -l ${RMT_OVA_NAME}" &> ${LOG}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1
grep -q "No such file or directory" ${LOG}
[ $? -eq 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

echo ""

########################################
# Deploy the OVA file.
echo -n "Deploy to ${VM_NAME} ... "
runESXiCmd "${OVFTOOL} --noSSLVerify --acceptAllEulas --name=${VM_NAME} --datastore=`basename ${ESXI_DATASTORE_DIR}` ${ESXI_DATASTORE_DIR}/`basename ${OVA_FILE_NAME}` vi://${ESXI_USERNAME}:${ESXI_PASSWORD}@${ESXI_IP}" &> ${LOG}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

echo ""

########################################
echo -n "Get the VMID:"
echo -n "  Get list of VMs ... "
runESXiCmd "vim-cmd vmsvc/getallvms" &> ${LOG}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

echo -n "  Look for VM ${VM_NAME} ... "
VMID=`grep ${VM_NAME} ${LOG} | awk {'print $1'}`
[ -z "${VMID}" ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS} "Pass (${VMID}).\n"

echo ""

########################################
# Start the VM.
echo    "Boot the VM:"
echo -n "  Issuing \"Power On\" command ... "
runESXiCmd "vim-cmd vmsvc/power.on ${VMID}" &> ${LOG}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

# Wait to see it gets powered on.
echo -n "  Wait for \"power on\" state ... "
while true; do
	runESXiCmd "vim-cmd vmsvc/power.getstate ${VMID}" &> ${LOG}
	[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1
	grep -q "Powered on" ${LOG}
	[ $? -eq 0 ] && printResult ${RESULT_PASS} && break
	sleep 1
done

echo ""

########################################
# Delete the OVA file from the ESXi server.
echo -n "  Delete OVA file from ESXi server ... "
runESXiCmd "rm -f ${RMT_OVA_NAME}" &> ${LOG}
[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

echo ""

########################################
# Done.  Success.
printResult ${RESULT_PASS} "  `basename ${0}` Success.\n"
exit 0

