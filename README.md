aws-ssh
=======
This script automates some setup tasks for AWS EC2 instances, associates their
hostnames with short names, and provides the `aws ssh name` command to simplify
connecting to them.

Installing
----------
Copy the script to your `bin` directory.

Initialize the configuration directory `~/.aws` and generate common SSH keys
with:
```sh
aws init
```

Linux instances
---------------
Associate the hostname with the short name `my-rhel`, check that connecting
works, and optionally use `yum` to update and install some additional packages:
```sh
aws build my-rhel ec2-ip.compute-1.amazonaws.com linux --yum 'group:Development Tools,screen'
```

Afterwards, connect with:
```sh
aws ssh my-rhel
```

Windows instances
-----------------
Associate the hostname and Windows password (obtained from the AWS console by
uploading `aws-windows.pem`) with the short name `my-windows`, generate a
`setup.bat` that installs Cygwin, OpenSSH, and some optional additional
packages, and connect to the desktop to run it:
```sh
aws build my-windows ec2-ip.compute-1.amazonaws.com windows password --cygwin gcc,screen
```

Afterwards, connect with:
```sh
aws ssh my-windows
aws rdesktop my-windows
```
