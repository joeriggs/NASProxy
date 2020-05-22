
This is just the tip of the iceberg for how the proxy starts.  But I wanted to
have a README file, and this is the starting point.

The following scripts will currently install and start the proxy.  And they'll
add a single encrypted NFS directory.  POC!  That's all it is right now.

- proxyConfig.sh
  Creates the /etc/pfproxy.conf file.  This contains all of the configuration
  information for the ProtectFile Proxy.

- dcInstall.sh
  If you need to create a Windows Domain Controller, create it now.  You will
  need the /etc/pfproxy.conf file that was created by proxyConfig.sh.

- proxyInstall.sh
  Install and initialize ProtectFile onto the ProtectFile Proxy.

    - proxyStart.sh
      Start the ProtectFile Proxy.  This script starts all of the important
      players (ProtectFile, NFSD, proxy FUSE driver, etc.) in the correct order.
      It loads all of the currently encrypted directories

        - dirAddNFS.sh
          Encrypt an NFS directory and add it to the ProtectFile Proxy.

        - dirDelNFS.sh
          Remove an NFS directory from the ProtectFile Proxy, and unencrypt it.

    - proxyStop.sh
      Shutdown the ProtectFile Proxy.  This includes stopping ProtectFile and
      disconnecting all of the mounts and exported directories.

- proxyUninstall.sh
  Unconfigure and remove ProtectFile from the ProtectFile Proxy.

