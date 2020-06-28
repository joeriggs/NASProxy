Name:           NAS_Proxy
Version:        0.1
Release:        1
Summary:        NAS Proxy
License:        GPLv3+

Requires: nfs-utils

%description 
The NAS Proxy is a Virtual Machine that serves as a proxy in front of a NAS.

%define _src_dir ${TOP_DIR}
%define _src_bin_dir %{_src_dir}/bin
%define _src_drv_dir %{_src_dir}/driver
%define _src_etc_dir %{_src_dir}/etc
%define _src_lib_dir %{_src_dir}/lib

%define _dst_dir /usr/local
%define _dst_bin_dir %{_dst_dir}/bin
%define _dst_etc_dir %{_dst_dir}/etc
%define _dst_lib_dir %{_dst_dir}/lib

%define _usr_lib_sys_dir /usr/lib/systemd/system
%define _etc_sys_dir     /etc/systemd/system

%build

%install

mkdir -p ${RPM_BUILD_ROOT}/%{_dst_bin_dir}
mkdir -p ${RPM_BUILD_ROOT}/%{_dst_etc_dir}
mkdir -p ${RPM_BUILD_ROOT}/%{_dst_lib_dir}

mkdir -p ${RPM_BUILD_ROOT}/%{_usr_lib_sys_dir}
mkdir -p ${RPM_BUILD_ROOT}/%{_etc_sys_dir}

cp %{_src_bin_dir}/proxyAdmin.sh                        ${RPM_BUILD_ROOT}/%{_dst_bin_dir}/proxyAdmin.sh
cp %{_src_bin_dir}/proxyStart.sh                        ${RPM_BUILD_ROOT}/%{_dst_bin_dir}/proxyStart.sh

cp %{_src_drv_dir}/proxy_bridge                         ${RPM_BUILD_ROOT}/%{_dst_bin_dir}/proxy_bridge

cp %{_src_etc_dir}/NASProxy.conf                        ${RPM_BUILD_ROOT}/%{_dst_etc_dir}/NASProxy.conf
cp %{_src_etc_dir}/NASProxyDirs.conf                    ${RPM_BUILD_ROOT}/%{_dst_etc_dir}/NASProxyDirs.conf

cp %{_src_etc_dir}/systemd/system/NASProxy.service      ${RPM_BUILD_ROOT}/%{_usr_lib_sys_dir}/NASProxy.service

cp %{_src_lib_dir}/commonUtils                          ${RPM_BUILD_ROOT}/%{_dst_lib_dir}/commonUtils
cp %{_src_lib_dir}/ipUtils                              ${RPM_BUILD_ROOT}/%{_dst_lib_dir}/ipUtils
cp %{_src_lib_dir}/printUtils                           ${RPM_BUILD_ROOT}/%{_dst_lib_dir}/printUtils
cp %{_src_lib_dir}/proxyUtils                           ${RPM_BUILD_ROOT}/%{_dst_lib_dir}/proxyUtils
cp %{_src_lib_dir}/osVersion                            ${RPM_BUILD_ROOT}/%{_dst_lib_dir}/osVersion

%post

echo ">>>>>>>>>>>>>>>>>>>>>>>>"
echo "Create symbolic link to systemd service."
ln -s /usr/lib/systemd/system/NASProxy.service /etc/systemd/system/NASProxy.service
echo "<<<<<<<<<<<<<<<<<<<<<<<<"
echo ""

# Enable and start nfsd.
echo ">>>>>>>>>>>>>>>>>>>>>>>>"
echo "NFS SERVER OPERATIONS:"
echo "Start nfs-server:"
systemctl start nfs-server
echo "Enable nfs-server:"
systemctl enable nfs-server
echo "Get nfs-server status:"
systemctl status nfs-server
echo "<<<<<<<<<<<<<<<<<<<<<<<<"
echo ""

%preun

%files
%defattr(-,root,root)

%attr(0755,root,root) %{_dst_bin_dir} 
%attr(0644,root,root) %{_dst_etc_dir}/NASProxy.conf
%attr(0644,root,root) %{_dst_etc_dir}/NASProxyDirs.conf
%attr(0644,root,root) %{_usr_lib_sys_dir}/NASProxy.service
%attr(0755,root,root) %{_dst_lib_dir} 
