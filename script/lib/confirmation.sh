#!/bin/bash -u
# ******************************************************************************* 
#                        Confirmation and Passphrase setting 
# ******************************************************************************* 

function confirmation(){

	# Consistency check for the OVERWRITEINSTALL and ERASEALL
	if [ ${ERASEALL} -eq 1 -a ${OVERWRITEINSTALL} -eq 1 ] ; then 
		cat <<- HEREDOC 1>&2
		***** ERROR : Confliction between ERASEALL and OVERWRITEINATALL *****
		...ERASEALL = ${ERASEALL}
		...OVERWRITEINSTALL = ${OVERWRITEINSTALL}
		...Check configuration in config.txt

		...Installation process terminated..
		HEREDOC
		return 1 # with error status
	fi

	# Sanity check for volume group name
	if echo ${VGNAME} | grep "-" -i > /dev/null ; then	# "-" is found in the volume group name.
		cat <<- HEREDOC 1>&2
		***** ERROR : VGNAME is "${VGNAME}" *****
		..."-" is not allowed in the volume name. 
		...Check configuration in config.txt

		...Installation process terminated..
		HEREDOC
		return 1 # with error status
	fi # "-" is found in the volume group name.

	# Sanity check for root volume name
	if echo ${LVROOTNAME} | grep "-" -i > /dev/null ; then	# "-" is found in the volume name.
		cat <<- HEREDOC 1>&2
		***** ERROR : LVROOTNAME is "${LVROOTNAME}" *****
		..."-" is not allowed in the volume name. 
		...Check configuration in config.txt

		...Installation process terminated..
		HEREDOC
		return 1 # with error status
	fi # "-" is found in the volume name.

	# Sanity check for swap volume name
	if echo ${LVSWAPNAME} | grep "-" -i > /dev/null ; then	# "-" is found in the volume name.
		cat <<- HEREDOC 1>&2
		***** ERROR : LVSWAPNAME is "${LVSWAPNAME}" *****
		..."-" is not allowed in the volume name. 
		...Check configuration in config.txt

		...Installation process terminated..
		HEREDOC
		return 1 # with error status
	fi # "-" is found in the volume name.

	# For surre ask the config.sh is edited
	cat <<- HEREDOC

	The destination logical volume label is "${LVROOTNAME}"
	"${LVROOTNAME}" uses ${LVROOTSIZE} of the LVM volume group.
	Are you ready to install? [Y/N]
	HEREDOC
	read YESNO
	if [ ${YESNO} != "Y" -a ${YESNO} != "y" ] ; then
		cat <<- HEREDOC 1>&2

		...Installation process terminated..
		HEREDOC
		return 1 # with error status
	fi	# if YES

	# For sure ask ready to erase. 
	if [ ${ERASEALL} -eq 1 ] ; then
		echo "Are you sure you want to erase entire ${DEV}? [Y/N]"
		read YESNO
		if [ ${YESNO} != "Y" -a ${YESNO} != "y" ] ; then
			cat <<-HEREDOC 1>&2
		...Check config.sh. The variable ERASEALL is ${ERASEALL}.

		...Installation process terminated..
		HEREDOC
		return 1 # with error status
		fi	# if YES
	fi	# if erase all

	# ----- Set Passphrase -----
	# Input passphrase
	echo ""
	echo "Type passphrase for the disk encryption."
	read -sr PASSPHRASE
	export PASSPHRASE

	echo "Type passphrase again, to confirm."
	read -sr PASSPHRASE_C

	# Validate whether both are indentical or not
	if [ ${PASSPHRASE} != ${PASSPHRASE_C} ] ; then
		cat <<-HEREDOC 1>&2
		***** ERROR : Passphrase doesn't match *****

		...Installation process terminated..
		HEREDOC
		return 1 # with error status
	fi	# passphrase validation

	# succesfull return
	return 0
}
