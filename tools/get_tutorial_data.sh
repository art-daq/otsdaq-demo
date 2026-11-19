#!/bin/bash

# usage: --tutorial <tutorial name>
#
#   tutorial
#		e.g. ${TUTORIAL} or artdaq
#
#  example run:
#	./get_tutorial_data.sh --tutorial first_demo
#
#  The data comes from the branch <tutorial name> of https://github.com/art-daq/otsdaq_demo_data (set
#  OTS_TUTORIAL_DATA_REPO to another repository URL or path, e.g. a local clone, to test a branch).
#  A branch with a Data folder fills USER_DATA. A branch with folders Data_<name> and no Data folder
#  (the tutorial subsystems: several instances side by side) fills one folder Data_<name> next to USER_DATA
#  for each of them and leaves USER_DATA alone. Existing folders are kept as <folder>.bak<date>.
#

if ! [ -e setup_ots.sh ]; then
  echo "You must run this script from an OTSDAQ installation directory (where setup_ots.sh is)!"
  kdialog --sorry "You must run this script from an OTSDAQ installation directory!" 2>/dev/null
  exit 1
fi

Base=$PWD
#commenting out unique filename generation
# no need to keep more than one past log for standard users
#alloutput_file=$( date | awk -v "SCRIPTNAME=$(basename $0)" '{print SCRIPTNAME"_"$1"_"$2"_"$3"_"$4".script"}' )
#stderr_file=$( date | awk -v "SCRIPTNAME=$(basename $0)" '{print SCRIPTNAME"_"$1"_"$2"_"$3"_"$4"_stderr.script"}' )
#exec  > >(tee "$Base/log/$alloutput_file")
mkdir "$Base/script_log"  &>/dev/null #hide output
rm "$Base/script_log/$(basename $0).script" >/dev/null 2>&1
rm "$Base/script_log/$(basename $0)_stderr.script" >/dev/null 2>&1
exec  > >(tee "$Base/script_log/$(basename $0).script")
#exec 2> >(tee "$Base/script_log/$stderr_file")
exec 2> >(tee "$Base/script_log/$(basename $0)_stderr.script")


#setup default parameters
TUTORIAL='first_demo'

if [[ "$1"  == "--tutorial" && "x$2" != "x" ]]; then
	TUTORIAL="$2"
fi

#done with arguments, so  pop all arguments so that setup_ots does not get confused!
while [ "$#" -gt 0 ]; do
    arg="$1"
    echo -e "$(date +%d%h%y.%T) get_tutorial_data.sh [${LINENO}]  \t Popped arg: $arg"
    shift
done

echo -e "$(date +%d%h%y.%T) get_tutorial_data.sh [${LINENO}]  \t TUTORIAL \t= $TUTORIAL"
echo

shopt -s expand_aliases #allows for aliases in non-interactive mode (which apparently is critical depending on the temperment of the terminal)

source setup_ots.sh

echo -e "$(date +%d%h%y.%T) get_tutorial_data.sh [${LINENO}]  \t ********************************************************************************"
echo -e "$(date +%d%h%y.%T) get_tutorial_data.sh [${LINENO}]  \t ************ Gettings otsdaq tutorial Data (user settings, etc.)... ************"
echo -e "$(date +%d%h%y.%T) get_tutorial_data.sh [${LINENO}]  \t ********************************************************************************"
echo -e "$(date +%d%h%y.%T) get_tutorial_data.sh [${LINENO}]  \t "


if [ "x$USER_DATA" == "x" ]; then
	echo -e "$(date +%d%h%y.%T) get_tutorial_data.sh [${LINENO}]  \t Error!"
	echo -e "$(date +%d%h%y.%T) get_tutorial_data.sh [${LINENO}]  \t Environment variable USER_DATA not setup!"
	echo -e "$(date +%d%h%y.%T) get_tutorial_data.sh [${LINENO}]  \t To setup, use 'export USER_DATA=<path to user data>'"
	echo
	echo
	echo -e "$(date +%d%h%y.%T) get_tutorial_data.sh [${LINENO}]  \t (If you do not have a user data folder copy '<path to ots source>/otsdaq-demo/Data' as your starting point.)"
	echo
	exit 1 #add 1 to indicate error to caller, 0 on success
fi

#Steps:
# download tutorial user data
# bkup current user data
# move download user data into position


#attempt to mkdir for full path so that it exists to move the user data to
# assuming mkdir is non-destructive
PATH_ARR=$(echo ${USER_DATA} | tr '/' "\n")
UD_PATH=""
for UD_EL in ${PATH_ARR[@]}
do
	#echo $UD_EL
	#echo $UD_PATH
	mkdir $UD_PATH &>/dev/null #hide output
	UD_PATH="$UD_PATH/$UD_EL"
done

if [ "x$ARTDAQ_DATABASE_URI" == "x" ] || [[ "$ARTDAQ_DATABASE_URI" != filesystemdb://* ]]; then
	echo -e "$(date +%d%h%y.%T) get_tutorial_data.sh [${LINENO}]  \t Error."
	echo -e "$(date +%d%h%y.%T) get_tutorial_data.sh [${LINENO}]  \t Environment variable ARTDAQ_DATABASE_URI not setup correctly! ARTDAQ_DATABASE_URI=${ARTDAQ_DATABASE_URI}"
	echo -e "$(date +%d%h%y.%T) get_tutorial_data.sh [${LINENO}]  \t To setup, use a filesystem database path: 'export ARTDAQ_DATABASE_URI=filesystemdb://<path to database>'"
	echo -e "$(date +%d%h%y.%T) get_tutorial_data.sh [${LINENO}]  \t            e.g. filesystemdb:///home/ots_user/databases/filesystemdb/test_db"
	echo
	echo
	echo
	exit 1 #add 1 to indicate error to caller, 0 on success
fi

#Steps:
# download tutorial database
# bkup current database
# move download database into position

ADU_PATH=$(echo ${ARTDAQ_DATABASE_URI} | cut -d':' -f2)
echo -e "$(date +%d%h%y.%T) get_tutorial_data.sh [${LINENO}]  \t artdaq database filesystem URI Path = ${ADU_PATH}"

#attempt to mkdir for full path so that it exists to move the database to
# assuming mkdir is non-destructive
ADU_ARR=$(echo ${ADU_PATH} | tr '/' "\n")
ADU_PATH=""
for ADU_EL in ${ADU_ARR[@]}
do
	#echo $ADU_EL
	#echo $ADU_PATH
	mkdir $ADU_PATH &>/dev/null #hide output
	ADU_PATH="$ADU_PATH/$ADU_EL"
done

# download tutorial user data
echo
echo -e "$(date +%d%h%y.%T) get_tutorial_data.sh [${LINENO}]  \t *****************************************************"
echo -e "$(date +%d%h%y.%T) get_tutorial_data.sh [${LINENO}]  \t Downloading tutorial user data.."
echo
echo -e "$(date +%d%h%y.%T) get_tutorial_data.sh [${LINENO}]  \t git clone https://github.com/art-daq/otsdaq_demo_data -b ${TUTORIAL}"
echo

git clone ${OTS_TUTORIAL_DATA_REPO:-https://github.com/art-daq/otsdaq_demo_data.git} -b ${TUTORIAL} otsdaq_demo_data

#several instances (branch with Data_<name> folders and no Data folder)?
MULTI_INSTANCE=0
if ! [ -d otsdaq_demo_data/Data ] && ls -d otsdaq_demo_data/Data_* >/dev/null 2>&1; then
	MULTI_INSTANCE=1
	echo -e "$(date +%d%h%y.%T) get_tutorial_data.sh [${LINENO}]  \t The tutorial has several instances: $(cd otsdaq_demo_data; ls -d Data_* | tr '\n' ' ')"
fi

# bkup current user data
echo
echo -e "$(date +%d%h%y.%T) get_tutorial_data.sh [${LINENO}]  \t *****************************************************"
echo -e "$(date +%d%h%y.%T) get_tutorial_data.sh [${LINENO}]  \t Backing up current user data.."
echo
echo -e "$(date +%d%h%y.%T) get_tutorial_data.sh [${LINENO}]  \t mv ${USER_DATA} ${USER_DATA}.bak`date +%y%m%d%H%M%S`"
echo
if [ $MULTI_INSTANCE == 0 ]; then
	mv ${USER_DATA} ${USER_DATA}.bak`date +%y%m%d%H%M%S`
else
	echo -e "$(date +%d%h%y.%T) get_tutorial_data.sh [${LINENO}]  \t (several instances: ${USER_DATA} is left alone)"
fi

# move download user data into position
echo
echo -e "$(date +%d%h%y.%T) get_tutorial_data.sh [${LINENO}]  \t *****************************************************"
echo -e "$(date +%d%h%y.%T) get_tutorial_data.sh [${LINENO}]  \t Installing tutorial data as user data.."
echo
echo -e "$(date +%d%h%y.%T) get_tutorial_data.sh [${LINENO}]  \t mv otsdaq_demo_data/Data ${USER_DATA}"
echo
if [ $MULTI_INSTANCE == 0 ]; then
	mv otsdaq_demo_data/Data ${USER_DATA}
else
	INSTANCE_PARENT=$(dirname ${USER_DATA})
	for INSTANCE_DIR in otsdaq_demo_data/Data_*
	do
		INSTANCE_NAME=$(basename ${INSTANCE_DIR})
		[ -e ${INSTANCE_PARENT}/${INSTANCE_NAME} ] && mv ${INSTANCE_PARENT}/${INSTANCE_NAME} ${INSTANCE_PARENT}/${INSTANCE_NAME}.bak`date +%y%m%d%H%M%S`
		echo -e "$(date +%d%h%y.%T) get_tutorial_data.sh [${LINENO}]  \t mv ${INSTANCE_DIR} ${INSTANCE_PARENT}/${INSTANCE_NAME}"
		mv ${INSTANCE_DIR} ${INSTANCE_PARENT}/${INSTANCE_NAME}
	done
fi

echo
echo -e "$(date +%d%h%y.%T) get_tutorial_data.sh [${LINENO}]  \t *****************************************************"
echo
echo -e "$(date +%d%h%y.%T) get_tutorial_data.sh [${LINENO}]  \t otsdaq tutorial Data installed!"
echo
echo

# bkup current database
echo
echo -e "$(date +%d%h%y.%T) get_tutorial_data.sh [${LINENO}]  \t *****************************************************"
echo -e "$(date +%d%h%y.%T) get_tutorial_data.sh [${LINENO}]  \t Backing up current database.."
echo
echo -e "$(date +%d%h%y.%T) get_tutorial_data.sh [${LINENO}]  \t mv ${ADU_PATH} ${ADU_PATH}.bak`date +%y%m%d%H%M%S`"
echo
mv ${ADU_PATH} ${ADU_PATH}.bak`date +%y%m%d%H%M%S`

# move download user data into position
echo
echo -e "$(date +%d%h%y.%T) get_tutorial_data.sh [${LINENO}]  \t *****************************************************"
echo -e "$(date +%d%h%y.%T) get_tutorial_data.sh [${LINENO}]  \t Installing tutorial database as database.."
echo

#hard to be sure of depth of table folders, so check
if [ -d otsdaq_demo_data/databases/XDAQContextTable ]; then
	echo -e "$(date +%d%h%y.%T) get_tutorial_data.sh [${LINENO}]  \t mv otsdaq_demo_data/databases ${ADU_PATH}"
	mv otsdaq_demo_data/databases ${ADU_PATH}
elif [ -d otsdaq_demo_data/databases/filesystemdb/XDAQContextTable ]; then
	echo -e "$(date +%d%h%y.%T) get_tutorial_data.sh [${LINENO}]  \t mv otsdaq_demo_data/databases/filesystemdb ${ADU_PATH}"
	mv otsdaq_demo_data/databases/filesystemdb ${ADU_PATH}
else
	echo -e "$(date +%d%h%y.%T) get_tutorial_data.sh [${LINENO}]  \t mv otsdaq_demo_data/databases/filesystemdb/test_db ${ADU_PATH}"
	mv otsdaq_demo_data/databases/filesystemdb/test_db ${ADU_PATH}
fi

echo
echo -e "$(date +%d%h%y.%T) get_tutorial_data.sh [${LINENO}]  \t *****************************************************"
echo
echo -e "$(date +%d%h%y.%T) get_tutorial_data.sh [${LINENO}]  \t otsdaq tutorial database installed!"
echo
echo

echo
echo
echo -e "$(date +%d%h%y.%T) get_tutorial_data.sh [${LINENO}]  \t Cleaning up downloads.."
echo
echo -e "$(date +%d%h%y.%T) get_tutorial_data.sh [${LINENO}]  \t rm -rf otsdaq_demo_data"
echo
rm -rf otsdaq_demo_data

exit #will indicate 0 on success to caller
