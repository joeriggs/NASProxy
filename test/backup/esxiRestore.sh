#!/bin/bash

################################################################################
# You can specify the exact name of a single VM.  This will force the tool to
# restore that single VM instead of all VMs.
################################################################################

readonly BLD_DIR=$( cd `dirname ${0}`   && echo ${PWD} )
readonly TOP_DIR=$( cd ${BLD_DIR}/../.. && echo ${PWD} )

################################################################################
################################################################################
################################################################################
################################################################################

VM_NUMBER=0
deployOneFile() {
	local OVA_FILE_NAME=${1}
	local VM_NAME=${2}

	local RMT_OVA_NAME=${ESXI_DATASTORE_DIR}/`basename ${OVA_FILE_NAME}`

	VM_NUMBER=$(( VM_NUMBER + 1 ))

	echo "${VM_NUMBER} : Deploying ${VM_NAME}"

	# If there is already a VM with ths requested name, stop now.
	echo    "  Make sure the VM name is unique:"
	echo -n "    Get list of VMs ... "
	runESXiCmd "vim-cmd vmsvc/getallvms" &> ${LOG}
	[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

	echo -n "  Look for VM ${VM_NAME} ... "
	OLD_VMID=`grep ${VM_NAME} ${LOG} | awk {'print $1'}`
	[ ! -z "${OLD_VMID}" ] && printResult ${RESULT_FAIL} "Fail (${OLD_VMID}).\n" && exit 1 ; printResult ${RESULT_PASS}
	unset OLD_VMID

	# Verify the local copy of the OVA file exists.
	echo -n "  Verify ${OVA_FILE_NAME} exists ... "
	[ ! -f ${OVA_FILE_NAME} ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

	# Make sure the ovftool is installed.  We will need it.
	verifyOvftool 2

	# Delete the old OVA file from the ESXi server.
	echo -n "  Delete old OVA file from ESXi server ... "
	runESXiCmd "rm -f ${RMT_OVA_NAME}" &> ${LOG}
	[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

	echo -n "  Verify file is deleted ... "
	runESXiCmd "ls -l ${RMT_OVA_NAME}" &> ${LOG}
	[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1
	grep -q "No such file or directory" ${LOG}
	[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

	echo -n "  Upload file ... "
	runESXiSCPPut ${OVA_FILE_NAME} ${RMT_OVA_NAME}
	[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

	echo -n "  Verify upload ... "
	runESXiCmd "ls -l ${RMT_OVA_NAME}" &> ${LOG}
	[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1
	grep -q "No such file or directory" ${LOG}
	[ $? -eq 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

	# Deploy the OVA file.
	echo -n "  Deploy to ${VM_NAME} ... "
	runESXiCmd "${OVFTOOL} --noSSLVerify --acceptAllEulas --name=${VM_NAME} --datastore=`basename ${ESXI_DATASTORE_DIR}` ${ESXI_DATASTORE_DIR}/`basename ${OVA_FILE_NAME}` vi://${ESXI_USERNAME}:${ESXI_PASSWORD}@${ESXI_IP}" &> ${LOG}
	[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

	echo    "  Get the VMID:"
	echo -n "    Get list of VMs ... "
	runESXiCmd "vim-cmd vmsvc/getallvms" &> ${LOG}
	[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

	echo -n "    Look for VM ${VM_NAME} ... "
	VMID=`grep ${VM_NAME} ${LOG} | awk {'print $1'}`
	[ -z "${VMID}" ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS} "Pass (${VMID}).\n"

	# Delete the OVA file from the ESXi server.
	echo -n "  Delete OVA file from ESXi server ... "
	runESXiCmd "rm -f ${RMT_OVA_NAME}" &> ${LOG}
	[ $? -ne 0 ] && printResult ${RESULT_FAIL} && exit 1 ; printResult ${RESULT_PASS}

	echo ""
}

################################################################################
####   Processing starts here.
################################################################################

echo "Initialization:"

echo -n "  CD to the run directory (${BLD_DIR}) ... "
cd ${BLD_DIR}
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
loadBuildConfigFile 2

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


# Get the list of OVA files into our log file.
echo -n "Get the list of OVA files  ... "
ls ${BACKUP_DIR}/*.ova &> ${LOG}
echo "Done (`cat ${LOG} | wc -l` OVA files)." ; echo ""

#deployOneFile /mnt/hgfs/Virtual_Machines_Backup/ProtectFile/ova/KS_8_11_0.ova KS_8_11_0
#exit 0

OLD_IFS="${IFS}"
IFS="
"
for FILE in `cat ${LOG}`; do
	NAME=`basename ${FILE} | sed "s|.ova$||;"`

	deployOneFile "${FILE}" "${NAME}"
done
IFS=${OLD_IFS}


########################################
# Done.  Success.
printResult ${RESULT_PASS} "  `basename ${0}` Success.\n"
exit 0

