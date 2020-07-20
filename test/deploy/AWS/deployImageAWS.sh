#!/bin/bash

################################################################################
# Deploy the NASProxy.ova file to Amazon AWS.
#
# This shell script has a lot of hardcoded stuff in it.  That's probably fine,
# but we might need to change it someday.
################################################################################

readonly BLD_DIR=$( cd `dirname ${0}`    && echo ${PWD} )
readonly TOP_DIR=$( cd ${BLD_DIR}/../..  && echo ${PWD} )

readonly OVA_FILE_NAME=NASProxy.ova
readonly OVA_FILE_PATH=${TOP_DIR}/${OVA_FILE_NAME}

################################################################################
# Create the "vmimport" role if it doesn't already exist.
#
# Input:
#   LOGFILE - The name of the log file where we should dump any data that we
#             we want to save.
#
# Output:
#   0 - success.
#   1 - failure.
################################################################################
createVMImportRole() {
	local LOGFILE=${1}

	cat > /tmp/trust-policy.json << EOF
{
   "Version": "2012-10-17",
   "Statement": [
      {
         "Effect": "Allow",
         "Principal": { "Service": "vmie.amazonaws.com" },
         "Action": "sts:AssumeRole",
         "Condition": {
            "StringEquals":{
               "sts:Externalid": "vmimport"
            }
         }
      }
   ]
}
EOF

	aws iam create-role --role-name vmimport --assume-role-policy-document "file:///tmp/trust-policy.json" &> ${LOGFILE}
	local RC=$?

	# Get rid of the json file.
	rm -f /tmp/trust-policy.json

	# Return if success.
	[ ${RC} -eq 0 ] && return 0

	# Return if vmimport is already configured.
	grep -q "Role with name vmimport already exists." ${LOGFILE}
	[ $? -eq 0 ] && return 0

	# Everything else is an error.
	return 1
}

################################################################################
# Put the "vmimport" role policy if it doesn't already exist.
#
# Input:
#   LOGFILE - The name of the log file where we should dump any data that we
#             we want to save.
#
# Output:
#   0 - success.
#   1 - failure.
################################################################################
putVMimportRolePolicy() {
	local LOGFILE=${1}

	cat > /tmp/role-policy.json << EOF
{
   "Version":"2012-10-17",
   "Statement":[
      {
         "Effect": "Allow",
         "Action": [
            "s3:GetBucketLocation",
            "s3:GetObject",
            "s3:ListBucket" 
         ],
         "Resource": [
            "arn:aws:s3:::nas.proxy",
            "arn:aws:s3:::nas.proxy/*"
         ]
      },
      {
         "Effect": "Allow",
         "Action": [
            "s3:GetBucketLocation",
            "s3:GetObject",
            "s3:ListBucket",
            "s3:PutObject",
            "s3:GetBucketAcl"
         ],
         "Resource": [
            "arn:aws:s3:::nas.proxy",
            "arn:aws:s3:::nas.proxy/*"
         ]
      },
      {
         "Effect": "Allow",
         "Action": [
            "ec2:ModifySnapshotAttribute",
            "ec2:CopySnapshot",
            "ec2:RegisterImage",
            "ec2:Describe*"
         ],
         "Resource": "*"
      }
   ]
}
EOF

	aws iam put-role-policy --role-name vmimport --policy-name vmimport --policy-document "file:///tmp/role-policy.json" &> ${LOG}
	local RC=$?

	# Get rid of the json file.
	rm -f /tmp/role-policy.json

	# Return if success.
	[ ${RC} -eq 0 ] && return 0

	# Everything else is an error.
	return 1
}

################################################################################
# Import the OVA file into AWS.  This will essentially convert the OVA file to
# an AWS AMI.
#
# Input:
#   LOGFILE - The name of the log file where we should dump any data that we
#             we want to save.
#
# Output:
#   0 - success.
#   1 - failure.
################################################################################
importOVA() {
	local LOGFILE=${1}

	cat > /tmp/containers.json << EOF
[
  {
    "Description": "NASProxy OVA",
    "Format": "ova",
    "UserBucket": {
        "S3Bucket": "nas.proxy",
        "S3Key": "NASProxy.ova"
    }
}]
EOF

	aws ec2 import-image --description "NASProxy" --disk-containers "file:///tmp/containers.json" &> ${LOGFILE}
	local RC=$?

	# Get rid of the json file.
	rm -f /tmp/role-policy.json

	# Return if success.
	[ ${RC} -eq 0 ] && return 0

	# Everything else is an error.
	return 1
}

####################
# Create and initialize a log file.
readonly LOG=/tmp/`basename ${0}`.log
echo    "Log file (${LOG}):"
echo -n "  Delete ... "
rm -f ${LOG} &> /dev/null
[ $? -ne 0 ] && echo "Fail." && exit 1 ; echo "Pass."
echo -n "  Create ... "
touch ${LOG} &> /dev/null
[ $? -ne 0 ] && echo "Fail." && exit 1 ; echo "Pass."
echo ""

####################
# Make sure the user has an AWS IAM configured.
echo    "IAM configuration:"
echo -n "  Check for \"aws\" command ... "
which aws &> ${LOG}
if [ $? -ne 0 ]; then
	echo "Fail.  Run installCli.sh to install the AWS CLI."
	exit 1
fi
echo "Found."

echo -n "  Check for AWS Access Key ID ... "
aws configure get aws_access_key_id &> ${LOG}
if [ $? -ne 0 ]; then
	echo "Fail.  Run \"aws configure\" to save your security credentials."
	exit 1
fi
echo "Found."

# Need to have the "vmimport" role.
echo -n "  Check for \"vmimport\" role ... "
aws iam get-role --role-name vmimport &> ${LOG}
if [ $? -eq 0 ]; then
	echo "Found."
else
	echo "Missing."
	echo -n "    Create \"vmimport\" role ... "
	createVMImportRole ${LOG}
	if [ $? -eq 0 ]; then
		echo "Pass."
	else
		echo "Fail."
		exit 1
	fi
fi

echo -n "  Put role policy ... "
putVMimportRolePolicy ${LOG}
[ $? -ne 0 ] && echo "Fail." && exit 1 ; echo "Pass."

echo ""

####################
# Create an S3 bucket and upload the NAS Proxy OVA file.
echo    "Upload:"
echo -n "  Check for bucket ... "
aws s3 ls | grep -a " nas.proxy$" &> ${LOG}
if [ $? -eq 0 ]; then
       	echo "Found."
else
	echo "Missing."
	echo -n "    Create ... "
	aws s3 mb s3://nas.proxy &> ${LOG}
	[ $? -ne 0 ] && echo "Fail." && exit 1 ; echo "Pass."
fi

echo -n "  Upload ... "
aws s3 cp ${OVA_FILE_PATH} s3://nas.proxy/ &> ${LOG}
[ $? -ne 0 ] && echo "Fail." && exit 1 ; echo "Pass."

echo ""

####################
# Import the OVA file into AWS.
echo "Import:"
echo -n "  Import ... "
importOVA ${LOG}
[ $? -ne 0 ] && echo "Fail." && exit 1
TASK_ID=`grep '"ImportTaskId": ' ${LOG} | awk {'print $2'} | sed -e "s/\"//g;" -e "s/,//;"`
echo "Pass (ImportTaskId = ${TASK_ID})."

echo ""

####################
# Wait for it to complete.
COUNTER=0
TS_BEG=`date +%s`

while true; do
	COUNTER=$(( COUNTER + 1 ))
	TS_CUR=`date +%s`
	ELAPSED_SECONDS=$(( TS_CUR - TS_BEG ))
	printf "%5d: %5d seconds: Waiting ... " ${COUNTER} ${ELAPSED_SECONDS}

	# The following command reports the status of the "aws ec2 import-image"
	# command that we just executed.  You can sit in a loop and run this
	# command occasionally to track the progress.
	aws ec2 describe-import-image-tasks --import-task-ids ${TASK_ID} &> ${LOG}

	# Search the output from the command for one of the following:
	# "StatusMessage" indicates the command is still running.  This is the status
	#                 of the import operation.
	#
	# "SnapshotId": "snap-0d9caed7044176ce5" appears when the command is finished.
	#                 There will no longer be a "StatusMessage" message.  You can
	#                 scan your list of AMIs and see an image with this name.
	grep -q "StatusMessage" ${LOG} &> /dev/null
	if [ $? -eq 0 ]; then
		STATUS_MSG=`grep '"StatusMessage": ' ${LOG} | sed -e "s/^.*\"StatusMessage\": //;" -e "s/\"//g;" -e "s/,//;"`
		printf "(%s).          \r" "${STATUS_MSG}"
		sleep 30
	else
		# Is it done?
		grep -q "SnapshotId" ${LOG} &> /dev/null
		if [ $? -eq 0 ]; then
			SNAPSHOT_ID=`   grep '"SnapshotId": '   ${LOG} | sed -e "s/^.*\"SnapshotId\": //;"   -e "s/\"//g;" -e "s/,//;"`
			IMAGE_ID=`      grep '"ImageId": '      ${LOG} | sed -e "s/^.*\"ImageId\": //;"      -e "s/\"//g;" -e "s/,//;"`
			IMPORT_TASK_ID=`grep '"ImportTaskId": ' ${LOG} | sed -e "s/^.*\"ImportTaskId\": //;" -e "s/\"//g;" -e "s/,//;"`

			printf "Done                       \n"
			printf "            SnapshotId = %s\n" "${SNAPSHOT_ID}"
			printf "               ImageId = %s\n" ${IMAGE_ID}
			printf "          ImportTaskId = %s\n" ${IMPORT_TASK_ID}
			break
		fi
	fi
done

echo ""

####################
# Done.  Cleanup.
echo    "Cleanup:"
echo -n "  Delete OVA file ... "
aws s3 rm s3://nas.proxy/${OVA_FILE_NAME} &> ${LOG}
[ $? -ne 0 ] && echo "Fail." && exit 1 ; echo "Pass."

echo -n "  Remove bucket ... "
aws s3 rb s3://nas.proxy &> ${LOG}
[ $? -ne 0 ] && echo "Fail." && exit 1 ; echo "Pass."

echo ""

####################
echo "Success."
exit 0

