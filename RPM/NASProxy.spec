Name:           NAS_Proxy
Version:        0.1
Release:        1
Summary:        NAS Proxy
License:        GPLv3+

%description 
The NAS Proxy is a Virtual Machine that serves as a proxy in front of a NAS.

%define _src_dir ${TOP_DIR}
%define _src_drv_dir %{_src_dir}/driver
%define _src_bin_dir %{_src_dir}/bin
%define _src_lib_dir %{_src_dir}/lib

%define _dst_dir /usr/local
%define _dst_bin_dir %{_dst_dir}/bin
%define _dst_lib_dir %{_dst_dir}/lib

%build

%install

mkdir -p ${RPM_BUILD_ROOT}/%{_dst_bin_dir}
mkdir -p ${RPM_BUILD_ROOT}/%{_dst_lib_dir}

cp %{_src_drv_dir}/proxy_bridge       ${RPM_BUILD_ROOT}/%{_dst_bin_dir}/proxy_bridge

cp %{_src_bin_dir}/proxyConfig.sh     ${RPM_BUILD_ROOT}/%{_dst_bin_dir}/proxyConfig.sh

cp %{_src_lib_dir}/commonUtils        ${RPM_BUILD_ROOT}/%{_dst_lib_dir}/commonUtils
cp %{_src_lib_dir}/printUtils         ${RPM_BUILD_ROOT}/%{_dst_lib_dir}/printUtils

%post

%preun

%files
# A run-time list of kernel modules is generated in the install phase of
# packaging and this list is read in with the -f option
%defattr(-,root,root)

%attr(0755,root,root) %{_dst_bin_dir} 
%attr(0755,root,root) %{_dst_lib_dir} 
