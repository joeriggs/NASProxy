#!/bin/bash

readonly BLD_DIR=$( cd `dirname ${0}`    && echo ${PWD} )
readonly TOP_DIR=$( cd ${BLD_DIR}/../..  && echo ${PWD} )

readonly OVA_FILE_NAME=NASProxy.ova
readonly OVA_FILE_PATH=${TOP_DIR}/${OVA_FILE_NAME}

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
echo -n "  Check ... "
aws configure get aws_access_key_id &> ${LOG}
[ $? -ne 0 ] && echo "Fail." && exit 1 ; echo "Pass."

echo -n "  Create vmimport role ... "
aws iam create-role --role-name vmimport --assume-role-policy-document "file:///home/jriggs/NASProxy/test/AWS/trust-policy.json" &> ${LOG}
if [ $? -ne 0 ]; then
	grep -q "Role with name vmimport already exists." ${LOG}
	if [ $? -eq 0 ]; then
		echo "Already exists."
	else
		echo "Fail."
		exit 1
	fi
else
	echo "Pass."
fi

echo -n "  Put role policy ... "
aws iam put-role-policy --role-name vmimport --policy-name vmimport --policy-document "file:///home/jriggs/NASProxy/test/AWS/role-policy.json" &> ${LOG}
[ $? -ne 0 ] && echo "Fail." && exit 1 ; echo "Pass."

echo ""

####################
# Create an S3 bucket and upload the NAS Proxy OVA file.
echo    "Bucket:"
echo -n "  Check ... "
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
##### echo -n "  Import ... "
##### aws ec2 import-image --description "NASProxy VM" --disk-containers "file://C:\import\containers.json" &> ${LOG}
##### [ $? -ne 0 ] && echo "Fail." && exit 1 ; echo "Pass."

# NOTE THE OUTPUT FROM THE PREVIOUS COMMAND WILL INCLUDE THE FOLLOWING.
#
#     "ImportTaskId": "import-ami-0fdee75f7e8c152e4",
#
# ImportTaskId IS THE ID THAT YOU PASS TO THE "aws ec2 describe-import-image-tasks"
#              COMMANDS (SHOWN BELOW).

##### echo ""

# The following command will report the status of the "aws ec2 import-image"
# command that we just executed.  You can sit in a loop and run this command
# occasionally (maybe once per minute, or 30 seconds) to track the progress.

##### aws ec2 describe-import-image-tasks --import-task-ids import-ami-0fdee75f7e8c152e4

# Search the output from the command for one of the following:
# "StatusMessage" indicates the command is still running.  This is the status
#                 of the import operation.
#
# "SnapshotId": "snap-0d9caed7044176ce5" appears when the command is finished.
#                 There will no longer be a "StatusMessage" message.  You can
#                 scan your list of AMIs and see an image with this name.

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

