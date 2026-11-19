#!/bin/bash
# reset_ots_tutorial.sh
#	Launches the specified otsdaq tutorial. If no tutorial name is specified it will default to first_demo.
#
# usage: [--tutorial <tutorial name>] [-K | --killall]
#
#   -K | --killall
#		Also kill ALL otsdaq processes and hardware emulators of YOUR user on this node (every
#		install, not just this one): runs 'ots --hardkill' and 'killall -9 ots_udp_hw_emulator'.
#		Without it, only the ots processes of THIS install directory are stopped, and an
#		emulator that is already running is left alone. Use it when a stale emulator or ots from
#		another install is in the way.
#
#   tutorial
#		e.g. ${TUTORIAL} or artdaq
#
#  example run:
#	./reset_ots_tutorial.sh --tutorial first_demo
#
#	NOTE: if kdialog is not installed, this script might work better sourced to bypass kdialog prompts
#		e.g. source reset_ots_tutorial.sh --tutorial first_demo
#
# export KDIALOG_ALWAYS_YES=1	 # to force yes answer and no kdialog popups

#setup default parameters
TUTORIAL='first_demo'

echo
echo "  |"
echo "  |"
echo "  |"
echo " _|_"
echo " \ /"
echo "  - "
echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t ========================================================"
echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t\t usage: --help"
echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t\t usage: --list # to list recommended tutorial names"
echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t\t usage: --tutorial <tutorial name>"
echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t\t usage: -K | --killall   # also kill ALL your ots processes and emulators on this node (all installs)"
echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t"
echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t\t note: If no name provided, tutorial will default to '${TUTORIAL}'"
echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t"
echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t\t for example..."
echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t\t\t ./reset_ots_tutorial.sh --tutorial first_demo"
echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t"


#return  >/dev/null 2>&1 #return is used if script is sourced


echo
echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t Extracting parameters..."
echo

TUTORIALS_STRING="first_demo first_demo_waveform artdaq nim_plus iterator subsystems mu2e_roc mu2e_dcs slow_controls"

KILLALL_REQUESTED=0   # -K | --killall: also kill every ots process and emulator of this user on this node
USER_GAVE_TUTORIAL=0  # did the user name a tutorial? (if not, and kdialog works, they are asked)

while [[ "x$1" != "x" ]]; do
	case "$1" in
		--tutorial)
			if [[ "x$2" == "x" ]]; then
				echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t --tutorial needs a tutorial name. See above for usage."
				return  >/dev/null 2>&1 #return is used if script is sourced
				exit
			fi
			TUTORIAL="$2"
			USER_GAVE_TUTORIAL=1
			shift 2
			;;
		-K | --killall)
			KILLALL_REQUESTED=1
			shift
			;;
		--list | --help)
			echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t --list found. Listing recommended parameter values..."
			echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t\t Tutorials = ${TUTORIALS_STRING}"
			return  >/dev/null 2>&1 #return is used if script is sourced
			exit
			;;
		*)
			echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t Illegal parameters.. See above for usage."
			return  >/dev/null 2>&1 #return is used if script is sourced
			exit  #exit is used if script is run ./reset...
			;;
	esac
done



if ! [ -e setup_ots.sh ]; then
	echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t You must run this script from an OTSDAQ installation directory with a setup_ots.sh script!"
	return  >/dev/null 2>&1 #return is used if script is sourced
	exit  #exit is used if script is run ./reset...
fi

shopt -s expand_aliases #allows for aliases in non-interactive mode (which apparently is critical depending on the temperment of the terminal)

########################################
## The "subsystems" tutorial: three ots instances side by side
##	top (the top level), sub1 and sub2 (two subsystems), each with its own user data folder Data_<name>
##	and its own ports. They are chosen by the argument of setup_ots.sh:  source setup_ots.sh sub1
##	The names are written into setup_ots.sh by setup_ots_subsystems.sh (otsdaq/ai_scripts). After that
##	a plain 'source setup_ots.sh' lists the names and stops, so loading any other tutorial takes the
##	names out again.
########################################
SUBSYSTEMS_BEGIN="# >>> ots subsystems (ai_scripts/setup_ots_subsystems.sh) >>>"
SUBSYSTEMS_END="# <<< ots subsystems <<<"
SUBSYSTEMS_START_ORDER="sub1 sub2 top"	#the subsystems first: the top level shows a subsystem as failing until it is up
SUBSYSTEMS_SPECS="top:2115:2110:2111 sub1:2015:2010:2011 sub2:2215:2210:2211"	#name:main port:Configure UDP port:Macro Maker UDP port

# use the tool in OTS_TUTORIAL_TOOLS_DIR (to test a change), else download it
fetch_tutorial_tool() # <file name> <url>
{
	if [ -n "$OTS_TUTORIAL_TOOLS_DIR" ] && [ -f "$OTS_TUTORIAL_TOOLS_DIR/$1" ]; then
		cp "$OTS_TUTORIAL_TOOLS_DIR/$1" "$1"
	else
		fetch_url "$2" "$1"
	fi
}

stop_subsystem_instances()
{
	local name
	for name in $SUBSYSTEMS_START_ORDER; do
		( source ./setup_ots.sh $name >/dev/null 2>&1 && echo Y | ots --killall >/dev/null 2>&1 )
	done
}

remove_subsystems_block()
{
	awk -v b="$SUBSYSTEMS_BEGIN" -v e="$SUBSYSTEMS_END" '$0==b{skip=1} !skip{print} $0==e{skip=0}' setup_ots.sh > setup_ots.sh.new \
		&& mv setup_ots.sh setup_ots.sh.bak.`date +%y%m%d%H%M%S` && mv setup_ots.sh.new setup_ots.sh
}

# names and ports into setup_ots.sh, the paths of the subsystems into the database, the table definitions up to date
subsystems_tutorial_setup()
{
	local tool="$OTS_SOURCE/otsdaq/ai_scripts/setup_ots_subsystems.sh"
	if ! [ -f "$tool" ]; then
		fetch_url https://raw.githubusercontent.com/art-daq/otsdaq/develop/ai_scripts/setup_ots_subsystems.sh setup_ots_subsystems.sh
		chmod 755 setup_ots_subsystems.sh; tool=./setup_ots_subsystems.sh
	fi
	"$tool" "$PWD" $SUBSYSTEMS_SPECS
	[ "$tool" == "./setup_ots_subsystems.sh" ] && rm -f setup_ots_subsystems.sh

	#the tutorial database holds the placeholders TUTORIAL_PLACEHOLDER_USER, TUTORIAL_PLACEHOLDER_HOST and /TUTORIAL_PLACEHOLDER_OTS_DIR for the path of each subsystem
	local databasePath=$(echo ${ARTDAQ_DATABASE_URI} | cut -d':' -f2)
	echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t The subsystems are at $(id -un)@$(hostname -f):$PWD/Data_<name>"
	grep -rlE 'TUTORIAL_PLACEHOLDER_USER|TUTORIAL_PLACEHOLDER_HOST|TUTORIAL_PLACEHOLDER_OTS_DIR' "$databasePath" 2>/dev/null | \
		xargs -r sed -i -e "s#TUTORIAL_PLACEHOLDER_USER#$(id -un)#g" -e "s#TUTORIAL_PLACEHOLDER_HOST#$(hostname -f)#g" -e "s#/TUTORIAL_PLACEHOLDER_OTS_DIR#$PWD#g"

	local name
	for name in $SUBSYSTEMS_START_ORDER; do
		( source ./setup_ots.sh $name >/dev/null 2>&1 && export OTS_WIZ_MODE_MAIN_PORT=$OTS_MAIN_PORT && UpdateOTS.sh --tables >/dev/null 2>&1 )
	done
}

# start every instance, the subsystems first. $1 = "activate only": Wiz mode just activates the saved groups, then stop
start_subsystems_tutorial()
{
	local name
	for name in $SUBSYSTEMS_START_ORDER; do
		echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t Starting the instance '${name}'..."
		( source ./setup_ots.sh $name >/dev/null 2>&1
		  export OTS_WIZ_MODE_MAIN_PORT=$OTS_MAIN_PORT #Wiz mode of one instance must not take the port of another
		  ots --wiz #just to test activate the saved groups
		  if [ "$1" == "activate only" ]; then ots -k; else ots; fi )
		sleep 5
	done
	[ "$1" == "activate only" ] && return
	echo
	echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t Log in at the top level: http://$(hostname -f):2115/urn:xdaq-application:lid=200/"
	echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t The subsystems are at ports 2015 (sub1) and 2215 (sub2). Stop one instance with: source setup_ots.sh <name> && echo Y | ots -k"
}

if grep -qF "$SUBSYSTEMS_BEGIN" setup_ots.sh 2>/dev/null; then #setup_ots.sh knows the subsystem names: it needs one of them
	if [[ "$TUTORIAL" == "subsystems" ]]; then
		stop_subsystem_instances
		source setup_ots.sh top
	else
		echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t Stopping the subsystem instances and taking their names out of setup_ots.sh (a backup is made)..."
		stop_subsystem_instances
		remove_subsystems_block
		source setup_ots.sh
	fi
else
	source setup_ots.sh
fi

# Stop old processes before (re)starting the tutorial.
#	default:  only the ots processes of THIS install directory ('ots --killall' matches this install's
#	          Data/ path), so other installs and emulators of the same user keep running.
#	-K:       every ots process and every hardware emulator of this user on this node ('ots --hardkill').
# 'echo Y |' answers the "Are you sure" question of ots: this script already asked (or was told to
# bypass the question), and without it a non-interactive run silently aborts the kill.
stop_existing_ots()
{
	if [[ $KILLALL_REQUESTED == 1 ]]; then
		echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t -K given: killing ALL ots processes and emulators of user ${USER} on this node..."
		echo Y | ots --hardkill
		killall -9 ots_udp_hw_emulator >/dev/null 2>&1
	else
		echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t Stopping ots processes of this install only (use -K to kill all of yours on this node)..."
		echo Y | ots --killall
	fi
}

# Download URL to FILE: wget where available (Linux, unchanged), else curl (macOS ships curl, not wget).
fetch_url()
{
	if command -v wget >/dev/null 2>&1; then
		wget "$1" --no-check-certificate -O "$2"
	else
		curl -fsSL --insecure -o "$2" "$1"
	fi
}

# Start the hardware emulator on port 4000, unless one is already running (e.g. left by another install:
# a second one could not bind the port, and killing it would break that install).
start_emulator()
{
	if pgrep -f "ots_udp_hw_emulator 4000" >/dev/null 2>&1; then
		echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t An ots_udp_hw_emulator on port 4000 is already running; leaving it. (Use -K to restart it.)"
	else
		ots_udp_hw_emulator 4000 &
	fi
}


echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t TUTORIAL \t= $TUTORIAL"
echo

#determine if kdialog is functional
# if not alias to echo


unalias kdialog >/dev/null 2>&1
KDIALOG_TEST="$(which kdialog 2>&1)"
echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t KDIALOG_TEST  \t= $KDIALOG_TEST"
echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t KDIALOG_ALWAYS_YES  \t= $KDIALOG_ALWAYS_YES"
echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t DISPLAY  \t= $DISPLAY"

if [[ "$KDIALOG_ALWAYS_YES" = 1 || "$KDIALOG_TEST" == *"no kdialog"* || "x$DISPLAY" == "x" ]]; then #no
	#instead of e.g. /usr/bin/kdialog
	# note: auto recognition only works if the script was sourced!

	alias kdialog="echo"
	which kdialog
	KDIALOG_ALWAYS_YES=1

	echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t kdialog is disabled, bypassing user prompts"
	echo


	Base=$PWD

	#commenting out unique filename generation
	# no need to keep more than one past log for standard users
	#alloutput_file=$( date | awk -v "SCRIPTNAME=$(basename $0)" '{print SCRIPTNAME"_"$1"_"$2"_"$3"_"$4".script"}' )
	#stderr_file=$( date | awk -v "SCRIPTNAME=$(basename $0)" '{print SCRIPTNAME"_"$1"_"$2"_"$3"_"$4"_stderr.script"}' )
	mkdir "$Base/script_log"  &>/dev/null #hide output
	SCRIPTNAME='reset_ots_tutorial'

	rm "$Base/script_log/${SCRIPTNAME}.script" >/dev/null 2>&1
	rm "$Base/script_log/${SCRIPTNAME}_stderr.script" >/dev/null 2>&1
	exec  > >(tee "$Base/script_log/${SCRIPTNAME}.script")
	exec 2> >(tee "$Base/script_log/${SCRIPTNAME}_stderr.script")

	echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t Script log saved here $Base/script_log/${SCRIPTNAME}.script and $Base/script_log/${SCRIPTNAME}_stderr.script"

	stop_existing_ots

	#download and run get_tutorial_data script
	rm -rf get_tutorial_data.sh >/dev/null 2>&1
	fetch_tutorial_tool get_tutorial_data.sh https://raw.githubusercontent.com/art-daq/otsdaq_demo/develop/tools/get_tutorial_data.sh
	chmod 755 get_tutorial_data.sh
	echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t Getting tutorial Data..."
	./get_tutorial_data.sh --tutorial ${TUTORIAL}
	exit_ret=$?
	echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t get_tutorial_data return code = $exit_ret"

	#clean up
	rm get_tutorial_data.sh

	if [ "$exit_ret" != 0 ]; then
		echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t Exiting...  get_tutorial_data failed with non-zero return code."
		unalias kdialog
		return  >/dev/null 2>&1 #return is used if script is sourced
		exit  #exit is used if script is run ./reset...
	fi

	#in case of minor table updates, update tables:
	UpdateOTS.sh --tables >/dev/null 2>&1

	if [[ "$TUTORIAL" == "subsystems" ]]; then
		subsystems_tutorial_setup
	fi

	#usually skip tutorial launch is run during quick_ots_install.sh
	if [ "$SKIP_TUTORIAL_LAUNCH" = 1 ]; then
		echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t Skipping tutorial launch flag is set..."

		if [[ "$TUTORIAL" == "subsystems" ]]; then
			start_subsystems_tutorial "activate only"
		else
			ots --wiz #just to test activate the saved groups
			ots -k
		fi

		echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t Tutorial reset script complete."
		unalias kdialog
		return  >/dev/null 2>&1 #return is used if script is sourced
		exit  #exit is used if script is run ./reset...
	fi

	echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t Launching tutorial..."

	if [[ "$TUTORIAL" == "subsystems" ]]; then
		start_subsystems_tutorial
	else
		ots --wiz #just to test activate the saved groups
		ots  #launch normal mode (and open firefox)
	fi

	#start hardware emulator on port 4000
	start_emulator

	echo
	echo
	echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t Tutorial reset script complete."

	unalias kdialog
	return  >/dev/null 2>&1 #return is used if script is sourced
	exit  #exit is used if script is run ./reset...
else
	KDIALOG_ALWAYS_YES=0
fi

#for testing KDIALOG ALWAYS
#echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t KDIALOG_ALWAYS_YES  \t= $KDIALOG_ALWAYS_YES"
#return  >/dev/null 2>&1 #return is used if script is sourced


if ! [ -e setup_ots.sh ]; then
  echo "You must run this script from an OTSDAQ installation directory (where setup_ots.sh is)!"
  kdialog --sorry "You must run this script from an OTSDAQ installation directory!" 2>/dev/null
  return  >/dev/null 2>&1 #return is used if script is sourced
  exit  #exit is used if script is run ./reset...
fi

echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t Using kdialog for tutorial reset."

Base=$PWD

#commenting out unique filename generation
# no need to keep more than one past log for standard users
#alloutput_file=$( date | awk -v "SCRIPTNAME=$(basename $0)" '{print SCRIPTNAME"_"$1"_"$2"_"$3"_"$4".script"}' )
#stderr_file=$( date | awk -v "SCRIPTNAME=$(basename $0)" '{print SCRIPTNAME"_"$1"_"$2"_"$3"_"$4"_stderr.script"}' )


mkdir "$Base/script_log"  &>/dev/null #hide output
SCRIPTNAME='reset_ots_tutorial'

rm "$Base/script_log/${SCRIPTNAME}.script" >/dev/null 2>&1
rm "$Base/script_log/${SCRIPTNAME}_stderr.script" >/dev/null 2>&1
exec  > >(tee "$Base/script_log/${SCRIPTNAME}.script")
exec 2> >(tee "$Base/script_log/${SCRIPTNAME}_stderr.script")

echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t Script log saved here $Base/script_log/${SCRIPTNAME}.script and $Base/script_log/${SCRIPTNAME}_stderr.script"


#Steps:
#	ask if user is sure they want to proceed to stop existing tutorial processes
#		if no, do nothing, done
#		if yes, stop processes and proceed
#
#	ask if user wants to reset tutorial data
#		if yes, replace user data and database with tutorial data
#		if no, do nothing and proceed
#
#	ask if user wants to startup tutorial processes
#		if no, do nothing, done
#		if yes, start emulator and normal mode



kdialog --yesno "This script starts otsdaq tutorials.\n\nBefore (re)starting the tutorial, this script will stop the existing ots processes of this installation (run with -K to stop all of yours on this node).\n\nDo you want to proceed?\n"
if [[ $KDIALOG_ALWAYS_YES == 0 && $? -eq 1 ]];then #no
	echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t User decided NOT to continue with starting the tutorial. Exiting script."
	kdialog --msgbox "You decided NOT to continue with starting the tutorial. Exiting script."

	return  >/dev/null 2>&1 #return is used if script is sourced
	exit
fi

stop_existing_ots

#if no parameters and kdialog is working, check which tutorial the user wants
if [[ $KDIALOG_ALWAYS_YES == 0 && $USER_GAVE_TUTORIAL == 0 ]]; then
	echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t No user parameters found, so checking which tutorial to run."

	kdialog --yesno "Do you want to proceed with the default tutorial, '${TUTORIAL}?'\n\n(if not, you will be prompted for tutorial name)"
	if [[ $? -eq 1 ]]; then #no

		TUTORIAL=$(kdialog --combobox "Please select the desired tutorial name:" "first_demo" "first_demo_waveform" "nim_plus" "iterator" "artdaq" "subsystems" --default "first_demo")

	fi

fi

echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t TUTORIAL \t= $TUTORIAL"
echo

kdialog --yesno "Do you want to reset user data and database for the '${TUTORIAL}' otsdaq tutorial (i.e. setup your ots installation for the beginning of the tutorial)?"
if [[ $KDIALOG_ALWAYS_YES == 1 || $? -eq 0 ]]; then #yes


	dbusRef=`kdialog --progressbar "Installing '${TUTORIAL}' tutorial user data and database..." 5`
	qdbus $dbusRef Set "" value 1

	echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t User decided to reset to '${TUTORIAL}' tutorial data."

	########################################
	########################################
	## Setup USER_DATA and databases
	########################################
	########################################

	#Take from tutorial data


	if [ "x$USER_DATA" == "x" ]; then
		echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t Error! You must already have ots setup (i.e. $USER_DATA must point to the right place)... For example, export USER_DATA=$MRB_SOURCE/otsdaq_demo/NoGitData. Exiting script."
		kdialog --msgbox "Error! You must already have ots setup (i.e. $USER_DATA must point to the right place)... For example, export USER_DATA=$MRB_SOURCE/otsdaq_demo/NoGitData. Exiting script."

		return  >/dev/null 2>&1 #return is used if script is sourced
		exit
	fi

	if [ "x$ARTDAQ_DATABASE_URI" == "x" ]; then
		#export ARTDAQ_DATABASE_URI="filesystemdb://$MRB_SOURCE/otsdaq_demo/NoGitDatabases/filesystemdb/test_db"
		echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t Error! You must already have ots setup (i.e. $ARTDAQ_DATABASE_URI must point to the right place)... For example, export USER_DATA=filesystemdb://$MRB_SOURCE/otsdaq_demo/NoGitDatabases/filesystemdb/test_db. Exiting script."
		kdialog --msgbox "Error! You must already have ots setup (i.e. $ARTDAQ_DATABASE_URI must point to the right place)... For example, export USER_DATA=$MRB_SOURCE/otsdaq_demo/NoGitData. Exiting script."

		return  >/dev/null 2>&1 #return is used if script is sourced
		exit
	fi

	#download get_tutorial_data script
	rm -rf get_tutorial_data.sh >/dev/null 2>&1
	fetch_tutorial_tool get_tutorial_data.sh https://raw.githubusercontent.com/art-daq/otsdaq_demo/develop/tools/get_tutorial_data.sh
	echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t Getting tutorial Data..."
	qdbus $dbusRef Set "" value 2

	#change permissions so the script is executable
	chmod 755 get_tutorial_data.sh

	#execute script
	./get_tutorial_data.sh --tutorial ${TUTORIAL}
	qdbus $dbusRef Set "" value 3

	#in case of minor table updates, update tables:
	UpdateOTS.sh --tables >/dev/null 2>&1

	if [[ "$TUTORIAL" == "subsystems" ]]; then
		subsystems_tutorial_setup
	fi

	########################################
	########################################
	## END Setup USER_DATA and databases
	########################################
	########################################

	qdbus $dbusRef close


    echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t Now your user data path is USER_DATA = ${USER_DATA}"
    echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t Now your database path is ARTDAQ_DATABASE_URI = ${ARTDAQ_DATABASE_URI}"

	#clean up
	rm get_tutorial_data.sh
fi


########################################
########################################
## START extra steps for specific tutorials
########################################
########################################


if [[ "$TUTORIAL"  == "nim_plus" ]]; then

	echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t Starting the ${TUTORIAL} tutorial extra steps..."
	mv install_ots_repo.sh install_ots_repo.sh.bk >/dev/null 2>&1
	fetch_url https://raw.githubusercontent.com/art-daq/otsdaq_prepmodernization/develop/tools/install_ots_repo.sh install_ots_repo.sh
	source install_ots_repo.sh #install prep modernization repo and table definitions
	rm -rf install_ots_repo.sh
	mv install_ots_repo.sh.bk install_ots_repo.sh  >/dev/null 2>&1
	echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t Done with the ${TUTORIAL} tutorial extra steps."

else
	echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t No extra steps needed for the ${TUTORIAL} tutorial."
fi

########################################
########################################
## END extra steps for specific tutorials
########################################
########################################


kdialog --yesno "Do you want to start the otsdaq tutorial processes (i.e. the emulator and ots in normal mode)?"
if [[ $KDIALOG_ALWAYS_YES == 1 || $? -eq 1 ]];then #no
	echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t User decided NOT to start the tutorial. Exiting script."
	kdialog --msgbox "You decided NOT to start the tutorial. Exiting script."
	return  >/dev/null 2>&1 #return is used if script is sourced
	exit
fi

#if script is sourced, stop here before running executables
return  >/dev/null 2>&1 #return is used if script is sourced


echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t User decided to start up the tutorial."

if [[ "$TUTORIAL" == "subsystems" ]]; then #the three instances, then the emulator
	start_subsystems_tutorial
	start_emulator
	return  >/dev/null 2>&1 #return is used if script is sourced
	exit
fi

dbusRef=`kdialog --progressbar "Starting tutorial and launching ots..." 7`
qdbus $dbusRef Set "" value 1

ots --wiz #just to test activate the saved groups
qdbus $dbusRef Set "" value 2

sleep 3 #give time to activate configuration
qdbus $dbusRef Set "" value 3
sleep 3 #give time to activate configuration
qdbus $dbusRef Set "" value 4
sleep 3 #give time to activate configuration
qdbus $dbusRef Set "" value 5

#start hardware emulator on port 4000
start_emulator
qdbus $dbusRef Set "" value 6

kdialog --yesno "Do you want this script to launch your web browser?"
if [[ $KDIALOG_ALWAYS_YES == 1 || $? -eq 1 ]];then #no
	echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t User decided NOT to launch web browser. Exiting script."
	ots
	qdbus $dbusRef Set "" value 7
	qdbus $dbusRef close
	kdialog --msgbox "You decided NOT to launch web browser. Tutorial reset script complete."
	return  >/dev/null 2>&1 #return is used if script is sourced
	exit
fi

ots --firefox #launch normal mode and open firefox
qdbus $dbusRef Set "" value 7

echo
echo
echo -e "$(date +%d%h%y.%T) reset_ots_tutorial.sh:${LINENO}  \t Tutorial reset script complete."

rm -f /tmp/postdata$$ /tmp/at_p$$ $REDMINE_LOGIN_COOKIEF $REDMINE_LOGIN_LISTF*; unset SKIP_REDMINE_LOGIN

qdbus $dbusRef close

kdialog --msgbox "Tutorial reset script complete."
