#!/bin/bash

readonly LOG=/tmp/`basename ${0}`.log
echo    "Log file (${LOG}):"
echo -n "  Delete ... "
rm -f ${LOG} &> /dev/null
[ $? -ne 0 ] && echo "Fail." && exit 1 ; echo "Pass."

echo -n "  Create ... "
touch ${LOG} &> /dev/null
[ $? -ne 0 ] && echo "Fail." && exit 1 ; echo "Pass."

echo "Installer:"
echo -n "  Download ... "
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" &> ${LOG}
[ $? -ne 0 ] && echo "Fail." && exit 1 ; echo "Pass."

echo -n "  Unzip ... "
unzip awscliv2.zip &> ${LOG}
[ $? -ne 0 ] && echo "Fail." && exit 1 ; echo "Pass."

echo -n "  Install ... "
sudo ./aws/install &> ${LOG}
[ $? -ne 0 ] && echo "Fail." && exit 1 ; echo "Pass."

exit 0

