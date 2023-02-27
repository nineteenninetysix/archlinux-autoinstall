DESCRIPTION:
I use archlinux and this is my automated deployment script. It will only go through the install process of wiki.archlinux.org including some of the "hardening" tutorials from the same domain.
There is a script to use standard MBR partitioning and a script to use LVM partitioning.
The script will also create 3 users - one to login (potrebitel); one to upgrade packages (devel); one to administer the systemem and escalate to root if needed;
Additionally the following packages will be installed and configured:
base base-devel linux-hardened linux-hardened-headers linux-firmware vim man-db man-pages texinfo bash-completion amd-ucode sudo grub apparmor firejail openssh lvm2 #<-- This is only installed in the LVM version.

NOTE:
As it is usually the case with archlinux, this script will give you a "sane" configuration according to myself and my use cases..
The script is not intended as a replacement to the installation guide in wiki.archlinux.org
Prior to use please review the *.sh files and understand the commands that are ran to ensure this works for you.

AUTHOR:
96-fromsofia - 2A9-7CC@96-fromsofia.net || August 2021

