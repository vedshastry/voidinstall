#!/bin/bash -u

function main() {
	# Load configuration parameter
	source config.sh

	# Load functions
	source lib/confirmation.sh
	source lib/preinstall.sh
	source lib/parainstall_msg.sh


	# This is the mount point of the install target. 
	export TARGETMOUNTPOINT="/target"

	# Distribution check
	if ! uname -a | grep ubuntu -i > /dev/null  ; then	# "Ubuntu" is not found in the OS name.
		echo "*******************************************************************************"
		uname -a
		cat <<- HEREDOC 
		*******************************************************************************
		This system seems to be not Ubuntu, while this script is dediated to the Ubuntu.
		Are you sure you want to run this script? [Y/N]
		HEREDOC
		read YESNO
		if [ ${YESNO} != "Y" -a ${YESNO} != "y" ] ; then
			cat <<- HEREDOC 1>&2

			...Installation process terminated..
			HEREDOC
			return 1 # with error status
		fi	# if YES

	fi # "Ubuntu" is not found in the OS name.

	# ******************************************************************************* 
	#                                Confirmation before installation 
	# ******************************************************************************* 

	# Common part of the parameter confirmation
	if ! confirmation ; then
		return 1 # with error status
	fi

	# ******************************************************************************* 
	#                                Pre-install stage 
	# ******************************************************************************* 

	# Common part of the pre-install stage
	if ! pre_install ; then
		return 1 # with error status
	fi


	# ******************************************************************************* 
	#                                Para-install stage 
	# ******************************************************************************* 

	# Show common message to let the operator focus on the critical part
	parainstall_msg

	# Ubuntu dependent message
	cat <<- HEREDOC

	************************ CAUTION! CAUTION! CAUTION! ****************************
	
	Make sure to click "Continue Testing",  at the end of the Ubiquity installer.
	Just exit the installer without rebooting. Other wise, your system
	is unable to boot. 

	Type return key to start Ubiquity.
	HEREDOC

	# waitfor a console input
	read dummy_var

	# Start Ubiquity installer 
	ubiquity &

	# Record the PID of the installer. 
	export INSTALLER_PID=$!

	# Common part of the para-install. 
	# Record the install PID, modify the /etc/default/grub of the target, 
	# and then, wait for the end of sintaller. 
	if ! grub_check_and_modify_ubuntu ; then
		return 1 # with error status
	fi

	# ******************************************************************************* 
	#                                Post-install stage 
	# ******************************************************************************* 

	# Finalizing. Embedd encryption key into the ramfs image. 
	post_install_void()

	# Normal end
	return 0

}	# End of main()


# ******************************************************************************* 
# Ubuntu dependent post-installation process
function post_install_ubuntu() {
	## Mount the target file system
	# ${TARGETMOUNTPOINT} is created by the GUI/TUI installer
	echo "...Mounting /dev/mapper/${VGNAME}-${LVROOTNAME} on ${TARGETMOUNTPOINT}."
	mount /dev/mapper/${VGNAME}-${LVROOTNAME} ${TARGETMOUNTPOINT}

	# And mount other directories
	echo "...Mounting all other dirs."
	for n in proc sys dev etc/resolv.conf; do mount --rbind "/$n" "${TARGETMOUNTPOINT}/$n"; done

	# Change root and create the keyfile and ramfs image for Linux kernel. 
	echo "...Chroot to ${TARGETMOUNTPOINT}."
	cat <<- HEREDOC | chroot ${TARGETMOUNTPOINT} /bin/bash
	# Mount the rest of partitions by target /etc/fstab
	mount -a

	# Set up the kernel hook of encryption
	echo "...Installing cryptsetup-initramfs package."
	apt -qq install -y cryptsetup-initramfs

	# Prepare a key file to embed in to the ramfs.
	echo "...Prepairing key file."
	mkdir /etc/luks
	dd if=/dev/urandom of=/etc/luks/boot_os.keyfile bs=4096 count=1 status=none
	chmod u=rx,go-rwx /etc/luks
	chmod u=r,go-rwx /etc/luks/boot_os.keyfile

	# Add a key to the key file. Use the passphrase in the environment variable. 
	echo "...Adding a key to the key file."
	printf %s "${PASSPHRASE}" | cryptsetup luksAddKey -d - "${DEV}${CRYPTPARTITION}" /etc/luks/boot_os.keyfile

	# Add the LUKS volume information to /etc/crypttab to decrypt by kernel.  
	echo "...Adding LUKS volume info to /etc/crypttab."
	echo "${CRYPTPARTNAME} UUID=$(blkid -s UUID -o value ${DEV}${CRYPTPARTITION}) /etc/luks/boot_os.keyfile luks,discard" >> /etc/crypttab

	# Putting key file into the ramfs initial image
	echo "...Registering key file to the ramfs"
	echo "KEYFILE_PATTERN=/etc/luks/*.keyfile" >> /etc/cryptsetup-initramfs/conf-hook
	echo "UMASK=0077" >> /etc/initramfs-tools/initramfs.conf

	# Finally, update the ramfs initial image with the key file. 
	echo "...Upadting initramfs."
	update-initramfs -uk all

	# Leave chroot
	HEREDOC

	# Unmount all
	echo "...Unmounting all."
	umount -R ${TARGETMOUNTPOINT}

	# Finishing message
	cat <<- HEREDOC
	****************** Post-install process finished ******************

	...Ready to reboot.
	HEREDOC

	retrun 0

} # End of post_install_ubuntu()


# ******************************************************************************* 
# This function will be executed in the foreguround context, to watch the GUI installer. 
function grub_check_and_modify_ubuntu() {

	# While the /etc/default/grub in the install target is NOT existing, keep sleeping.
	# If installer terminated without file copy, this script also terminates.
	while [ ! -e ${TARGETMOUNTPOINT}/etc/default/grub ]
	do
		sleep 1 # 1sec.

		# Check if installer still exist
		if ! ps $INSTALLER_PID  > /dev/null ; then	# If not exists
			cat <<-HEREDOC 1>&2
			***** ERROR : The GUI/TUI installer terminated unexpectedly. ***** 
			...Deleting the new logical volume "${VGNAME}-${LVROOTNAME}".
			HEREDOC
			lvremove -f /dev/mapper/${VGNAME}-${LVROOTNAME} 
			echo "...Deactivating all logical volumes in volume group \"${VGNAME}\"."
			vgchange -a n ${VGNAME}
			echo "...Closing LUKS volume \"${CRYPTPARTNAME}\"."
			cryptsetup close  ${CRYPTPARTNAME}
			cat <<-HEREDOC 1>&2

			...The new logical volume has been deleted. You can retry Kaiten-yaki again. 
			...Installation process terminated.
			HEREDOC
			return 1 # with error status
		fi
	done # while

	# Perhaps, too neuvous. Wait 1 more sectond to avoid the rece condition.
	sleep 1 # 1sec.

	# Make target GRUB aware to the crypt partition
	# This must do it after start of the file copy by installer, but before the end of the file copy.
	echo "...Adding GRUB_ENABLE_CRYPTODISK entry to ${TARGETMOUNTPOINT}/etc/default/grub "
	echo "GRUB_ENABLE_CRYPTODISK=y" >> ${TARGETMOUNTPOINT}/etc/default/grub

	# And then, wait for the end of installer process
	echo "...Waiting for the end of GUI/TUI installer."
	echo "...Again, DO NOT reboot/restart here. Just exit the GUI/TUI installer."
	wait $INSTALLER_PID

	# succesfull return
	return 0

} # grub_check_and_modify_ubuntu()

# ******************************************************************************* 
# Execute
main