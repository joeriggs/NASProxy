
This is a "NAS Proxy".  It's a virtual machine (a.k.a. VM) that can sit in front of your NAS server(s) and provide additional services (such as file encryption) that the NAS doesn't provide.

Build requirements:
In order to build the NAS Proxy, you must meet a few requirements:
1. Build on a Linux computer.  I've been using CentOS 8.1.  I don't know about other distributions.  But I do know it makes extensive use of the "yum" utility.
2. Access to an ESXi server.  The NAS Proxy is built into an OVA file, and it uses an ESXi server as the build platform.  I've been building with the free license for an ESXi 5.5 server.
3. The ESXi server has ssh/scp enabled.
4. ovftool is installed on the ESXi server.  If you create a vmware account, you can download and install ovftool onto a Linux computer.  Once it's installed, you can copy it to the ESXi server.

Once you've met the requirements, you can build the OVA file by running ./build.sh.  The build.sh script can build 2 different types of product:
1. NAS Proxy -  This git project contains all of the data required to build a copy of the NAS Proxy.  If you want to build a NAS Proxy, just run "./build.sh".

2. NAS Encryptor - If you specify the environment variable NAS_ENCRYPTOR_DIR, then this build tool will build the NAS Encryptor.  It will expect NAS_ENCRYPTOR_DIR to point to a directory that is a copy of the https://github.com/joeriggs/NASEncryptor project.

Once you've built the OVA file (it will be located in ./NASProxy.ova on your build computer), you can deploy it to your ESXi server by running ./test/deployVM.sh.  deployVM.sh will upload the OVA file to the ESXi server, deploy it, and start it.

Once the NAS Proxy is running on your ESXi server, you can access it from the system console.  Log in as admin/password.
