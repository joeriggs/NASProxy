#!/bin/bash

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
aws s3 cp NASProxy.ova s3://nas.proxy/ &> ${LOG}
[ $? -ne 0 ] && echo "Fail." && exit 1 ; echo "Pass."

echo ""

exit 0

####################
# Import the OVA file into AWS.
echo -n "  Upload ... "
aws s3 cp NASProxy.ova s3://nas.proxy/ &> ${LOG}
aws ec2 import-image --description "NASProxy VM" --disk-containers "file://C:\import\containers.json"
[ $? -ne 0 ] && echo "Fail." && exit 1 ; echo "Pass."

echo ""

####################
# Done.  Cleanup.
echo    "Cleanup:"
echo -n "  Delete OVA file ... "
aws s3 rm s3://nas.proxy/NASProxy.ova
[ $? -ne 0 ] && echo "Fail." && exit 1 ; echo "Pass."

echo -n "  Remove bucket ... "
aws s3 rb s3://nas.proxy
[ $? -ne 0 ] && echo "Fail." && exit 1 ; echo "Pass."
echo ""

echo "Success."
exit 0

