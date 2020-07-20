#!/bin/bash

################################################################################
# A quick smoke test to see if the NAS Proxy is running correctly.  This doesn't
# attempt to beat it to death.  It just runs a quick test to see if it's loaded
# correctly.
################################################################################

readonly PROXY_IP=192.168.111.232
readonly PROXY_EXPORT=/export/nfsDir
readonly PROXY_MOUNT_POINT=/mnt/nfsDir

readonly NAS_IP=192.168.111.235
readonly NAS_EXPORT=/export/nfsDir
readonly NAS_MOUNT_POINT=/mnt/nas

echo "Create mount point directories: =========================================="
sudo mkdir -p ${PROXY_MOUNT_POINT} ${NAS_MOUNT_POINT}
[ $? -ne 0 ] && echo "Fail." && exit 1 ; echo "Pass." ; echo ""

echo "Execute showmount: ======================================================="
showmount -e ${PROXY_IP}
[ $? -ne 0 ] && echo "Fail." && exit 1 ; echo "Pass." ; echo ""

echo "Mount NAS Proxy exported drive: =========================================="
sudo mount ${PROXY_IP}:${PROXY_EXPORT} ${PROXY_MOUNT_POINT}
[ $? -ne 0 ] && echo "Fail." && exit 1 ; echo "Pass." ; echo ""

echo "Mount directly to NAS: ==================================================="
sudo mount -t nfs -o nfsvers=3 ${NAS_IP}:${NAS_EXPORT} ${NAS_MOUNT_POINT}
[ $? -ne 0 ] && echo "Fail." && exit 1 ; echo "Pass." ; echo ""

echo "Doing an ls -l: =========================================================="
ls -l ${PROXY_MOUNT_POINT}
[ $? -ne 0 ] && echo "Fail." && exit 1 ; echo "Pass." ; echo ""

echo "Doing a cat: ============================================================="
cat ${PROXY_MOUNT_POINT}/*
[ $? -ne 0 ] && echo "Fail." && exit 1 ; echo "Pass." ; echo ""

echo "Unmount NAS Proxy exported drive: ========================================"
sudo umount ${PROXY_MOUNT_POINT}
[ $? -ne 0 ] && echo "Fail." && exit 1 ; echo "Pass." ; echo ""

echo "Unmount direct NAS: ======================================================"
sudo umount ${NAS_MOUNT_POINT}
[ $? -ne 0 ] && echo "Fail." && exit 1 ; echo "Pass." ; echo ""

echo "Delete mount point directories: =========================================="
sudo rmdir ${PROXY_MOUNT_POINT} ${NAS_MOUNT_POINT}
[ $? -ne 0 ] && echo "Fail." && exit 1 ; echo "Pass." ; echo ""

echo "Test passed."
exit 0

