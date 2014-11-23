#!/bin/bash

#
# xymon-omsa-raid.sh	External script for Big Brother
#
# Local RAID monitoring for Dell PowerEdge RAID Controllers (PERC) in 
# conjunction with Dell's OpenManage Server Administration (OMSA) tool 
# called 'omreport'.
#

#
# Known to work on the following Dell RAID controllers:
#
#	SCSI
#	----
#	Adaptec PERC2, PERC2/Si					     - ROMB
#	LSI Logic PERC2/SC, PERC2/DC, PERC2/QC			     - Add-in
#	Adaptec PERC3/Si, PERC3/Di				     - ROMB
#	LSI Logic PERC3/SC, PERC3/DC, PERC3/DCL, PERC3/QC 	     - Add-in
#	LSI Logic PERC4/Si, PERC4/Di, PERC4/IM			     - ROMB
#	LSI Logic PERC4/SC, PERC4/DC, PERC4/QC			     - Add-in
#	LSI Logic PERC4e/Si, PERC4e/Di				     - ROMB
#	LSI Logic PERC4e/DC					     - Add-in
#	LSI Logic PERC5/i, PERC5/iR				     - ROMB
#	LSI Logic PERC5/E					     - Add-in
#	LSI Logic PERC6/i, PERC6/iR				     - ROMB
#	LSI Logic PERC6/E					     - Add-in
#
#	ATA
#	---
#	LSI Logic CERC ATA 100/4ch				     - Add-in
#	Adaptec CERC SATA1.5/6ch, SATA1.5/2s			     - ROMB
#

#
# Revision History:
# V1.0	2005-11-08 Original version by Ben Argyle
# 	bda20@cam.ac.uk -- Ben Argyle, University of Cambridge
# V1.1	2005-11-24 Minor bugfixes/updates suggested by Ricardo M. Stella
#		Fix to work with PCI slot cards properly
#		Fix to work with controllers without batteries
#		Some cosmetic changes
#		Verified compatiblity with certain CERCs
#	bda20@cam.ac.uk -- Ben Argyle, University of Cambridge
# V1.2	2005-12-01 Minor bugfixes to doeal with capitalisation issues
#	bda20@cam.ac.uk -- Ben Argyle, University of Cambridge
# V1.3  2007-01-02 Functionality fix suggestions by Shane Presley
#		Fix to work with PERC5 cards, also
#		Superfluous report lines removed but verbosity increased
#		 (sorry if this isn't what you wanted)
#		Fixed typos and errors in some comments
#	bda20@cam.ac.uk - Ben Argyle, University of Cambridge
# V1.4	2009-03-16 Functionality fix suggestion by Gabriel Petrescu
#		Fix to work with PERC6 cards while remaining backwards 
#		 compatible with older PERCs, also
#		Fix to work with OMSA 5.0.0 and greater
#		Minor clean up to code here and there
#	bda20@cam.ac.uk - Ben Argyle, University of Cambridge
# V1.5 2014-11-23 Fix for subshell issues with multiple controllers
#   spiderr@bitweaver.org
# 
#
# This script is public-domain software and may be modified
# as you wish.  If you do, please include the revision history.
#

#
# This program is (loosely) based on the sample monitoring
# script distributed with Big Brother, and released under 
# the same restrictions as Big Brother.
#


#
# XYMONPROG should just contain the name of this file
# Useful when you get environment dumps to locate
# the offending script
#
XYMONPROG=omsa-raid.sh; export XYMONPROG


#
# TEST will become a column on the display
# It should be as short as possible to save space...
# Note you can also create a help file for your test
# which should be put in www/help/$TEST.html.  It will
# be linked into the display automatically.
#
TEST="raid"


#########################################################
#
# For testing purposes only
# Uncomment if you're not running this within Big Brother
# and you want output to screen rather than just the file
# and not send the data to the Big Brother server
#
#export XYMONHOME=/usr/lib/xymon/client
#########################################################


if test ! "$XYMONHOME"
then
	echo "${XYMONPROG}: XYMONHOME is not set"
	exit 1
fi

if test ! -d "$XYMONHOME"
then
	echo "${XYMONPROG}: XYMONHOME is invalid"
	exit 1
fi

#
# Set up global variables/files
#
DATE=`date`
RAID_CONTROLLERS=$XYMONTMP/xymon_omsa-raid-controllers.tmp
CHECK_CONTROLLERS=$XYMONTMP/xymon_omsa-raid-check-controllers.tmp
CHECK_VIRTUAL_DISKS=$XYMONTMP/xymon_omsa-raid-check-virtual-disks.tmp
FILE_OMREPORT_BATTERY=$XYMONTMP/xymon_omsa-raid-data-battery.tmp
FILE_OMREPORT_STORAGE_VDISK=$XYMONTMP/xymon_omsa-raid-data-storage-vdisk.tmp
FILE_OMREPORT_STORAGE_PDISK=$XYMONTMP/xymon_omsa-raid-data-storage-pdisk.tmp
OMREPORT=/opt/dell/srvadmin/bin/omreport
RAW_OMSA=`$OMREPORT about -fmt ssv | grep Version | cut -d";" -f2`
OMSA_VERSION=`echo $RAW_OMSA | tr -d "."`

#
# Note that two of the files need to be created as 'rm' will 
# complain if they're not there.  They won't be used if the 
# test can't find anything wrong.
#
touch ${CHECK_CONTROLLERS} ${CHECK_VIRTUAL_DISKS} 

#
# Set the default overall COLOR (result) for the test.
#
COLOR="green"

set_color() {
	if [[ $COLOR != "red" ]]; then
		COLOR=$1
	fi
}

OUTPUT="\nDell PowerEdge RAID Controller (PERC/CERC) Status (OMSA v$RAW_OMSA)\n===============================================================\n"

$OMREPORT storage controller -fmt ssv | grep -v "Controller"  | grep -v "^$" | sed -e :a -e '$!N;s/\n;/;/;ta' -e 'P;D' > ${RAID_CONTROLLERS}

while read line 
do
	echo $line | grep "Slot ID" > /dev/null
	if [ $? -eq 0 ]; then

		cid_tag=`echo $line | cut -d";" -f1`
		cstatus_tag=`echo $line | cut -d";" -f2`
		cname_tag=`echo $line | cut -d";" -f3`
		cslot_id_tag=`echo $line | cut -d";" -f4`
		cstate_tag=`echo $line | cut -d";" -f5`
		cfirm_ver_tag=`echo $line | cut -d";" -f6`

	else 

		cid=`echo $line | cut -d";" -f1`
		cstatus=`echo $line | cut -d";" -f2`
		cname=`echo $line | cut -d";" -f3`
		cslot_id=`echo $line | cut -d";" -f4`
		cstate=`echo $line | cut -d";" -f5`
		cfirm=`echo $line | cut -d";" -f6`

		# Ascertain what model of PERC we're dealing with
		controller_type=`echo ${cname:5:1}`

		#
		# You can insert other tests here for fields such as
		# "Minimum Required Firmware Version" or "Alarm State" if you
		# wish.  Remember that the Controller's ID only needs to be 
		# added to $CHECK_CONTROLLERS once if it's got a non-green result.
		#
		# Possible Controller States:		Possible Controller Statuses:
		# Unknown				Other
		# Ready					Unknown
		# Failed				Ok
		# Online				Non-critical
		# Offline				Critical
		# Degraded				Non-recoverable
		#

		echo $cid >> ${CHECK_CONTROLLERS}

		lowercase_cstatus=`echo $cstatus | tr A-Z a-z`

		if [[ $lowercase_cstatus == "non-critical" ]]; then
			cstatus_colour="&yellow"
			set_color "yellow"
		elif [[ $lowercase_cstatus == "ok" ]]; then
			cstatus_colour="&green"
		else
			cstatus_colour="&red"
			set_color "red"
		fi

		if [[ $cstate == "Degraded" ]]; then
			cstate_colour="&yellow"
			set_color "yellow"
		elif [[ $cstate == "Ready" ]]; then
			cstate_colour="&green"
		else
			cstate_colour="&red"
			set_color "red"
		fi

		OUTPUT+="\nController $cid | Controller type is a PERC $controller_type"
		OUTPUT+="\n-------------------------------------------"
		OUTPUT+="\n&clear $cid_tag                                : $cid"
		OUTPUT+="\n$cstatus_colour $cstatus_tag                            : $cstatus"
		OUTPUT+="\n&clear $cname_tag                              : $cname"
		OUTPUT+="\n&clear $cslot_id_tag                           : $cslot_id"
		OUTPUT+="\n$cstate_colour $cstate_tag                             : $cstate"
		OUTPUT+="\n&clear $cfirm_ver_tag                  : $cfirm"

		$OMREPORT storage battery controller=$cid -fmt ssv | grep -v "Controller" | grep -v "^$" | grep -iv "No Batteries found" > ${FILE_OMREPORT_BATTERY}

		while read line; do
			echo $line | grep Recharge > /dev/null
			if [ $? -eq 0 ]; then

				bstatus_tag=`echo $line | cut -d";" -f2`
				bstate_tag=`echo $line | cut -d";" -f4`

			else

				bstatus=`echo $line | cut -d";" -f2`
				bstate=`echo $line | cut -d";" -f4`

#
# You can insert other tests here for fields such as
# "Recharge count" if you wish.
#
# Possible Battery States:	Possible Battery Statuses:
# Unknown			Other
# Ready				Unknown
# Failed			Ok
# Reconditioning		Non-critical
# High				Critical
# Low				Non-recoverable
# Charging
# Missing
#

				lowercase_bstatus=`echo $bstatus | tr A-Z a-z`

				if [[ $lowercase_bstatus == "non-critical" ]]; then
					bstatus_colour="&yellow"
					set_color "yellow"
				elif [[ $lowercase_bstatus == "ok" ]]; then
					bstatus_colour="&green"
				else
					bstatus_colour="&red"
					set_color "red"
				fi

				if [[ $bstate == "Reconditioning" || $bstate == "Charging" || $bstate == "Learning" ]]; then
					bstate_colour="&yellow"
					set_color "yellow"
				elif [[ $bstate == "Ready" ]]; then
					bstate_colour="&green"
				else
					bstate_colour="&red"
					set_color "red"
				fi

				OUTPUT+="\n# Battery : Controller $cid"
				OUTPUT+="\n#"
				OUTPUT+="\n# $bstatus_colour $bstatus_tag : $bstatus"
				OUTPUT+="\n# $bstate_colour $bstate_tag  : $bstate"
	
			fi

		done < ${FILE_OMREPORT_BATTERY}

	fi

done < ${RAID_CONTROLLERS} 

OUTPUT+="\n-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-\n"

#
# Now check the Virtual Disks on the 'bad controllers' and display them 
# in a similar manner to the Controllers, with their array disks below.
#

while read controller; do
	$OMREPORT storage vdisk controller=$controller -fmt ssv | grep -v "Controller" | grep -v "^$" > ${FILE_OMREPORT_STORAGE_VDISK}
	while read line; do 
		echo $line | grep Layout > /dev/null
		if [ $? -eq 0 ]; then
	
			vid_tag=`echo $line | cut -d";" -f1`
			vstatus_tag=`echo $line | cut -d";" -f2`
			vname_tag=`echo $line | cut -d";" -f3`
			vstate_tag=`echo $line | cut -d";" -f4`
			vprogress_tag=`echo $line | cut -d";" -f5`
			vlayout_tag=`echo $line | cut -d";" -f6`
	
		else
		
			vid=`echo $line | cut -d";" -f1`
			vstatus=`echo $line | cut -d";" -f2`
			vname=`echo $line | cut -d";" -f3`
			vstate=`echo $line | cut -d";" -f4`
			vprogress=`echo $line | cut -d";" -f5`
			vlayout=`echo $line | cut -d";" -f6`
		
#
# You can insert other tests here for a field such as
# "Progress" if you wish.  Remember that the Controller's 
# ID only needs to be added to $CHECK_VIRTUAL_DISKS once if 
# it's got a non-green result.
#
# Possible Virtual Disk States:		Possible Virtual Disk Statuses:
# Unknown				Other
# Ready					Unknown
# Failed				Ok
# Online				Non-critical
# Offline				Critical
# Degraded				Non-recoverable
# Resynching
# Regenerating
# Rebuilding
# Formatting
# Reconstructing
# Initializing
# Background Initialization
#

			lowercase_vstatus=`echo $vstatus | tr A-Z a-z`

			echo $vid >> ${CHECK_VIRTUAL_DISKS}

			if [[ $lowercase_vstatus == "non-critical" ]]; then
				vstatus_colour="&yellow"
				set_color "yellow"
			elif [[ $lowercase_vstatus == "ok" ]]; then
				vstatus_colour="&green"
			elif [[ $lowercase_vstatus == "no virtual disks found" ]]; then
				vstatus_colour="&clear"
			else
				vstatus_colour="&red"
				set_color "red"
			fi
	
			if [[ $vstate == "Degraded" ]]; then
				vstate_colour="&yellow"
				set_color "yellow"
			elif [[ $vstate == "Ready" ]]; then
				vstate_colour="&green"
			elif [[ $vstate == "No virtual disks found" ]]; then
				vstate_colour="&clear"
			else
				vstate_colour="&red"
					set_color "red"
			fi
	
			OUTPUT+="\nVirtual Disk $vid : Controller $controller"
			OUTPUT+="\n-------------------------------"
			OUTPUT+="\n&clear $vid_tag           : $vid"
			OUTPUT+="\n$vstatus_colour $vstatus_tag       : $vstatus"
			OUTPUT+="\n&clear $vname_tag         : $vname"
			OUTPUT+="\n$vstate_colour $vstate_tag        : $vstate"
			OUTPUT+="\n&clear $vprogress_tag     : $vprogress"
			OUTPUT+="\n&clear $vlayout_tag       : $vlayout"

			# Check to make sure we have a numerical $vid
			if [ "$vid" -eq "$vid" ] 2>/dev/null; then
				$OMREPORT storage pdisk vdisk=$vid controller=$controller -fmt ssv | grep -v "List" | grep -v "Controller" | grep -v "^$" > ${FILE_OMREPORT_STORAGE_PDISK}
				while read line; do
					echo $line | grep Progress > /dev/null
					if [ $? -eq 0 ]; then

						aid_tag=`echo $line | cut -d";" -f1`
						astatus_tag=`echo $line | cut -d";" -f2`
						aname_tag=`echo $line | cut -d";" -f3`
						astate_tag=`echo $line | cut -d";" -f4`

						if [ $OMSA_VERSION -lt 500 ]; then
							aprogress_tag=`echo $line | cut -d";" -f5`
						else
							afail_pred_tag=`echo $line | cut -d";" -f5`
							aprogress_tag=`echo $line | cut -d";" -f6`
						fi

					else

						aid=`echo $line | cut -d";" -f1`
						astatus=`echo $line | cut -d";" -f2`
						aname=`echo $line | cut -d";" -f3`
						astate=`echo $line | cut -d";" -f4`

						if [ $OMSA_VERSION -lt 500 ]; then
							aprogress=`echo $line | cut -d";" -f5`
						else
							afail_pred=`echo $line | cut -d";" -f5`
							aprogress=`echo $line | cut -d";" -f6`
						fi

#
# You can insert other tests here for fields such as
# "Progress" or "Hot Spare" if you wish.  At this point we
# don't use a file to store 'bad' array disks, so there's 
# no check for adding a disk more than once.
#
# Possible Array Disk States:		Possible Array Disk Statuses:
# Ready					Other
# Failed				Unknown
# Online				Ok
# Offline				Non-critical
# Degraded				Critical
# Recovering				Non-recoverable
# Removed					
# Resyncing				
# Rebuild					
# Formatting				
# Diagnostics				
#
# Possible Failure Predicted Values:
# Yes
# No
#

						lowercase_astatus=`echo $astatus | tr A-Z a-z`
						OUTPUT+="\n***$lowercase_astatus***"
						if [[ $lowercase_astatus == "non-critical" ]]; then
							astatus_colour="&yellow"
							set_color "yellow"
						elif [[ $lowercase_astatus == "ok" ]]; then
							astatus_colour="&green"
						else
							astatus_colour="&red"
							set_color "red"
						fi

						if [[ $astate == "Degraded" ]]; then
							astate_colour="&yellow"
							set_color "yellow"
						elif [[ $astate == "Ready" || $astate == "Online" ]]; then
							astate_colour="&green"
						else
							astate_colour="&red"
							set_color "red"
						fi

						if [ $OMSA_VERSION -ge 500 ]; then
							if [[ $afail_pred == "Yes" ]]; then
								afail_colour="&red"
								set_color "red"
							elif [[ $afail_pred == "No" ]]; then
								afail_colour="&green"
							elif [[ $afail_pred == "Not Applicable" ]]; then
								afail_colour="&clear"
							else
								afail_colour="&red"
								set_color "red"
							fi
						fi

						OUTPUT+="\n# Array Disk $aid : Virtual Disk $vid : Controller $controller"
						OUTPUT+="\n#"
						OUTPUT+="\n# &clear $aid_tag                        : $aid"
						OUTPUT+="\n# $astatus_colour $astatus_tag                    : $astatus"
						OUTPUT+="\n# &clear $aname_tag                      : $aname"
						OUTPUT+="\n# $astate_colour $astate_tag                     : $astate"

						if [ $OMSA_VERSION -ge 500 ]; then
							OUTPUT+="\n# $afail_colour $afail_pred_tag         : $afail_pred"
							OUTPUT+="\n# &clear $aprogress_tag                  : $aprogress"
						else
							OUTPUT+="\n# &clear $aprogress_tag                  : $aprogress"
						fi

					fi 
				done < ${FILE_OMREPORT_STORAGE_PDISK}
				OUTPUT+="\n-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-\n"
			fi
		fi
	done < ${FILE_OMREPORT_STORAGE_VDISK}
done < ${CHECK_CONTROLLERS} 

#
# Create the line we'll send to Big Brother
#
LINE="status $MACHINE.$TEST $COLOR $DATE RAID Status: `echo -e $OUTPUT`"


#########################################################
#
# For testing purposes only
# Uncomment if you're not running this within Big Brother
# and you want output to screen rather than just the file
# and not send the data to the Big Brother server
# Additionally, comment out the line beginning $XYMON below
#
#echo $XYMONDISP "$LINE"
#########################################################

#
# Otherwise send the line
#
$XYMON $XYMSRV "$LINE"


#
# Clean up our temporary files
#
rm ${RAID_CONTROLLERS}
rm ${CHECK_CONTROLLERS}
rm ${CHECK_VIRTUAL_DISKS}
rm ${FILE_OMREPORT_BATTERY}
rm ${FILE_OMREPORT_STORAGE_VDISK}
rm ${FILE_OMREPORT_STORAGE_PDISK}

