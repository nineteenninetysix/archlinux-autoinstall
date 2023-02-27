#!/bin/bash

# Vars
os_disk=/dev/sda
time_zone=""
hostname=""
vps_ip=""
vps_gw=""
vps_dns=""
potr_pass=$(openssl rand -base64 10)
dev_pass=$(openssl rand -base64 14)
adm_pass=$(openssl rand -base64 14)
root_pass=$(openssl rand -base64 100)
grub_pass=$(openssl rand -base64 8)
ssh_port=$(shuf -i 14206-65091 -n1)
ssh_file=/etc/ssh/sshd_config
fw_file=/etc/iptables/iptables.rules

function osinstall {
        # Ensure system clock is accurate
        timedatectl set-ntp true
        # Create FS layout
        (echo o; echo n; echo ""; echo ""; echo ""; echo ""; echo t; echo 30; echo w) | fdisk $os_disk
        yes | pvcreate $(echo $os_disk)1
        yes | vgcreate OS-volume $(echo $os_disk)1
        yes | lvcreate -L 4GB OS-volume -n swap
        yes | lvcreate -L 3GB OS-volume -n root
        yes | lvcreate -L 1GB OS-volume -n home
        yes | lvcreate -L 1GB OS-volume -n tmp
        yes | lvcreate -L 10GB OS-volume -n usr
        yes | lvcreate -L 2GB OS-volume -n var
        yes | lvcreate -L 2GB OS-volume -n var_log
        yes | lvcreate -l 100%FREE OS-volume -n var_mail
        modprobe dm_mod
        vgscan
        vgchange -ay
        mkswap /dev/OS-volume/swap
        swapon /dev/OS-volume/swap
        mkfs.ext4 /dev/OS-volume/root
        mkfs.ext4 /dev/OS-volume/home
        mkfs.ext4 /dev/OS-volume/tmp
        mkfs.ext4 /dev/OS-volume/usr
        mkfs.ext4 /dev/OS-volume/var
        mkfs.ext4 /dev/OS-volume/var_log
        mkfs.ext4 /dev/OS-volume/var_mail
        mount /dev/OS-volume/root /mnt
        mkdir /mnt/home ; mount -o nodev,noexec,nosuid /dev/OS-volume/home /mnt/home
        mkdir /mnt/tmp ; mount -o nodev,noexec,nosuid /dev/OS-volume/tmp /mnt/tmp
        mkdir /mnt/usr ; mount -o nodev /dev/OS-volume/usr /mnt/usr
        mkdir /mnt/var ; mount -o nodev,noexec,nosuid /dev/OS-volume/var /mnt/var
        # Sort out mirrolist
        yes | pacman -Sy pacman-contrib
        cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist_back
        rankmirrors -n 6 /etc/pacman.d/mirrorlist_back > /etc/pacman.d/mirrorlist
        yes | pacman -Sy dialog
        sync ; pacstrap /mnt base base-devel linux-hardened linux-hardened-headers linux-firmware vim man-db man-pages texinfo bash-completion amd-ucode sudo grub apparmor firejail openssh lvm2
}

function ossetup {
        # Copy FSTAB and chroot
        genfstab -U /mnt >> /mnt/etc/fstab
        cd /mnt
        mount -t proc /proc proc/
        mount -t sysfs /sys sys/
        mount -o bind /dev dev/
        mount -o bind /run run/
        chroot /mnt /bin/bash << EOF

        # Fix environment
        source /etc/profile
        source ~/.bashrc

        # Fix time and locale
        ln -sf /usr/share/zoneinfo/$time_zone /etc/localtime
        hwclock --systohc
        sed -i "s/#en_US.UTF-8/en_US.UTF-8/" /etc/locale.gen
        locale-gen
        echo "LANG=en_US.UTF-8" > /etc/locale.conf

        # Set up network
        echo $hostname > /etc/hostname
        echo -e "127.0.0.1    localhost\n::1    localhost\n127.0.1.1    katya.localdomain    katya" > /etc/hosts
        for i in $vps_dns ; do echo -e "nameserver $i" >> /etc/resolv.conf ; done
        systemctl enable systemd-networkd
        systemctl enable systemd-resolved
        echo -e "[Match]\nName=enp0s3\n\n[Network]\nAddress=$vps_ip\nGateway=$vps_gw\nDNS=$vps_dns" > /etc/systemd/network/20-wired.network

        # Create users, tighten pam and sudo
        useradd -g users -s /bin/bash -m potrebitel
        useradd -g users -s /bin/bash -m devel
        useradd -g users -s /bin/bash -m admin
        (echo $potr_pass; echo $potr_pass) | passwd potrebitel
        (echo $dev_pass; echo $dev_pass) | passwd devel
        (echo $adm_pass; echo $adm_pass) | passwd admin
        sed -i 's/#auth         required        pam_wheel.so use_uid/auth               required        pam_wheel.so use_uid/' /etc/pam.d/{su,su-l}
        groupadd -r ssh ;
        for g in power ssh; do gpasswd -a potrebitel \$g ; done
        for g in network power storage; do gpasswd -a admin \$g ; done
        chown -R devel:root /etc/{vim*,ssh,bash*}
        sed -i 's/root ALL=(ALL) ALL/# root ALL=(ALL) ALL/' /etc/sudoers
        sed -i 's/@includedir/#@includedir/' /etc/sudoers
        echo -e 'Defaults    env_reset\nDefaults    editor=/usr/bin/rvim\nDefaults    passwd_timeout=0\nDefaults    timestamp_timeout=15\nDefaults    insults\nCmnd_Alias  POWER       =   /usr/bin/shutdown -h now, /usr/bin/halt, /usr/bin/poweroff, /usr/bin/reboot\nCmnd_Alias  STORAGE     =   /usr/bin/mount -o nosuid\,nodev\,noexec, /usr/bin/umount\nCmnd_Alias  SYSTEMD     =   /usr/bin/journalctl, /usr/bin/systemctl\nCmnd_Alias  KILL        =   /usr/bin/kill, /usr/bin/killall\nCmnd_Alias  PKGMAN      =   /usr/bin/pacman\nCmnd_Alias  NETWORK     =   /usr/bin/systemctl systemd-networkd, /usr/bin/systemctl systemd-resolved, /usr/bin/wg, /usr/bin/wg-quick\nCmnd_Alias  FIREWALL    =   /usr/bin/iptables, /usr/bin/ip6tables\nCmnd_Alias  SHELL       =   /usr/bin/zsh, /usr/bin/bash\n%power      ALL         =   (root)  NOPASSWD: POWER\n%network    ALL         =   (root)  NETWORK\n%storage    ALL         =   (root)  STORAGE\nroot        ALL         =   (ALL)   ALL\nadmin       ALL         =   (root)  SYSTEMD, KILL, FIREWALL, STORAGE, /usr/bin/bash\ndevel         ALL         =   (root)  PKGMAN\npotrebitel           ALL         =   (devel) SHELL, (admin) SHELL\n@includedir /etc/sudoers.d' >> /etc/sudoers
        chown -c root:root /etc/sudoers
        chmod -c 0440 /etc/sudoers
        echo "alias sudo='sudo -v; sudo '" >> /etc/bash.bashrc

        # Iptables
        cp $fw_file /root/.iptables_bk
        systemctl enable iptables
        iptables -F
        iptables -A INPUT -i lo -j ACCEPT
        iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
        iptables -A INPUT -p tcp --dport $ssh_port -j ACCEPT -m comment --comment "SSH ACCESS"
        iptables -A INPUT -p tcp --dport $ssh_port -m state --state NEW -m recent --set --name ssh --rsource -m comment --comment "SSH ACCESS"
        iptables -I INPUT -p tcp --dport $ssh_port -m state --state NEW -m recent ! --rcheck --seconds 90 --hitcount 3 --name ssh --rsource -j ACCEPT -m comment --comment "SSH ACCESS"
        iptables -P INPUT DROP
        iptables -P FORWARD DROP
        iptables -P OUTPUT ACCEPT
        iptables-save > $fw_file

        # SSH
        sed -i "s/#Port\ 22/Port\ $ssh_port/" $ssh_file
        sed -i 's/#AddressFamily\ any/AddressFamily\ inet/' $ssh_file
        sed -i 's/PermitRootLogin\ yes/PermitRootLogin\ no/' $ssh_file
        echo -e "AllowUsers potrebitel\nDenyUsers root devel admin\nProtocol 2" >> $ssh_file
        systemctl enable sshd

        # Misc hardening
        chmod 700 /boot /etc/{iptables,ssh,bash.bashrc}
        sed -i "s/umask 022/umask 0077/" /etc/profile
        echo -e "-:root:ALL\n+:admin:LOCAL\n-:admin:ALL\n-:devel:ALL\n+:potrebitel:ALL" >> /etc/security/access.conf
        systemctl enable apparmor.service
        echo -e 'TMOUT="$(( 60*10 ))";\n[ -z "$DISPLAY" ] && export TMOUT;\ncase $( /usr/bin/tty ) in\n    /dev/tty[0-9]*) export TMOUT;;\nesac\n' > /etc/profile.d/shell-timeout.sh
        echo -e 'net.ipv4.tcp_rfc1337 = 1\nnet.ipv4.conf.default.rp_filter = 1\nnet.ipv4.conf.all.rp_filter = 1\nnet.ipv6.conf.all.disable= = 1' > /etc/sysctl.d/99-sysctl.conf

        # Install GRUB
        sed -i 's/HOOKS=(base udev autodetect modconf block filesystems keyboard fsck)/HOOKS=(base systemd autodetect modconf block lvm2 filesystems keyboard fsck)/' /etc/mkinitcpio.conf
        mkinitcpio -P
        grub-install --target=i386-pc $os_disk
        (echo $grub_pass; echo $grub_pass) | grub-mkpasswd-pbkdf2 | tail -1 | rev | awk '{print \$1}' | rev > /root/.grub_passphrase.txt
        chown root:root /etc/grub.d/40_custom
        chmod 0700 /etc/grub.d/40_custom
        echo -e "set superusers=\"username\"\npassword_pbkdf2 username \$(cat /root/.grub_passphrase.txt)" >> /etc/grub.d/40_custom
        sed -i 's/CLASS="--class gnu-linux --class gnu --class os"/CLASS="--class gnu-linux --class gnu --class os --unrestricted"/' /etc/grub.d/10_linux
        sed -i 's/GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="lsm=lockdown,yama,apparmor,bpf,lockdown=confidentiality,ipv6.disable=1,root=\/dev\/OS-volume\/root"/' /etc/default/grub
        sed -i 's/GRUB_PRELOAD_MODULES="part_gpt part_msdos"/GRUB_PRELOAD_MODULES="part_gpt part_msdos lvm"/' /etc/default/grub
        grub-mkconfig -o /boot/grub/grub.cfg
        rm -rf /root/.grub_passphrase.txt
EOF
        cd /
}

function osexit {
        # Provide credentials and access info and ask if to reboot or exit script to shell
        echo -e "IP: $vps_ip\nSSH: $ssh_port\nPass: $potr_pass\nDev_Pass: $dev_pass\nAdm_Pass: $adm_pass\nGRUB: $grub_pass\n\nWould you like to reboot the box?" >> /mnt/root/credentials.txt
        dialog --yesno "$(cat /mnt/root/credentials.txt)\n\nCredentials and access info saved at: /mnt/root/credentials.txt\nWould you like to reboot the box?" 20 50
        ans=$?
        # Based on answer given either reboot or drop to shell
        if [ $ans == "0" ]
        then
                umount -R /mnt
                sleep 3
                sync
                shutdown -h now
        else
                echo "Goodbye! Dropping you to a shell now.."
                exit
        fi
}

osinstall
ossetup
osexit

