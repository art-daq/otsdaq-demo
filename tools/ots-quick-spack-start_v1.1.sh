#! /bin/bash
# quick-mrb-start.sh - Eric Flumerfelt, May 20, 2016
# Downloads, installs, and runs the artdaq_demo as an MRB-controlled repository

git_status=`git status 2>/dev/null`
git_sts=$?
if [ $git_sts -eq 0 ];then
    echo "This script is designed to be run in a fresh install directory!"
    exit 1
fi

echo "$0 $@" >$PWD/ots-quick-spack-start.lastrun.sh

starttime=`date`
Base=$PWD
test -d log || mkdir log
test -d Data && rmdir Data
test -d databases && rmdir databases

env_opts_var=`basename $0 | sed 's/\.sh$//' | tr 'a-z-.' 'A-Z__'`_OPTS
USAGE="\
   usage: `basename $0` [options] [demo_root]
examples: `basename $0` .
          `basename $0` --debug
          `basename $0` --tag v2_08_04
If the \"demo_root\" optional parameter is not supplied, the user will be
prompted for this location.
--debug       perform a debug build
--develop     Install the develop version of the software (may be unstable!)
--dev-only    Do not install otsdaq-suite in a local environment (use with --upstream!)
--tag         Install a specific tag of otsdaq
--spackdir    Install Spack in this directory (or use existing installation)
-a            Artdaq version number (e.g. 31300 for v3_13_00)
-s            Use specific qualifiers when building ots
-v            Be more verbose
-x            set -x this script
-w            Check out repositories read/write
--no-extra-products  Skip the automatic use of central product areas, such as CVMFS
--upstream    Use <dir> as a Spack upstream (repeatable)
--no-use-cvmfs Do not search /cvmfs/fermilab.opensciencegrid.org/products/artdaq/spack_v1.1 for upstreams
              If --upstream is used, CVMFS will not be automatically searched for upstreams
--padding     Set directory padding to 255, for relocatability
--no-view     Do not create Spack environment views
--arch        Architecture for build (Defaults to linux-almalinux9-x86_64_v3)
--host-arch   Use Spack-default arch
--no-kmod     Do not build TRACE kernel module (for Docker builds)
"

# Process script arguments and options
eval env_opts=\${$env_opts_var-} # can be args too

spackdir="${SPACK_ROOT:-$Base/spack}"
arch=""
upstreams=()
tag=develop
installStatus=0
eval "set -- $env_opts \"\$@\""
op1chr='rest=`expr "$op" : "[^-]\(.*\)"`   && set -- "-$rest" "$@"'
op1arg='rest=`expr "$op" : "[^-]\(.*\)"`   && set --  "$rest" "$@"'
reqarg="$op1arg;"'test -z "${1+1}" &&echo opt -$op requires arg. &&echo "$USAGE" &&exit'
args= do_help= opt_v=0; opt_w=0; opt_develop=0; opt_skip_extra_products=0; opt_no_pull=0; opt_padding=0; opt_no_kmod=0; opt_no_view=0; opt_dev_only=0; opt_use_cvmfs=1; opt_host_arch=0
while [ -n "${1-}" ];do
    if expr "x${1-}" : 'x-' >/dev/null;then
        op=`expr "x$1" : 'x-\(.*\)'`; shift   # done with $1
        leq=`expr "x$op" : 'x-[^=]*\(=\)'` lev=`expr "x$op" : 'x-[^=]*=\(.*\)'`
        test -n "$leq"&&eval "set -- \"\$lev\" \"\$@\""&&op=`expr "x$op" : 'x\([^=]*\)'`
        case "$op" in
            \?*|h*)              eval $op1chr; do_help=1;;
            v*)                  eval $op1chr; opt_v=`expr $opt_v + 1`;;
            x*)                  eval $op1chr; set -x;;
            a*)                  eval $op1arg; aqualifier=$1; shift;;
            s*)                  eval $op1arg; squalifier=$1; shift;;
            w*)                  eval $op1chr; opt_w=`expr $opt_w + 1`;;
            -debug)              opt_debug=--debug;;
            -develop)            opt_develop=1;;
            -dev-only)           opt_dev_only=1;;
            -tag)                eval $reqarg; tag=$1; shift;;
            -spackdir)           eval $op1arg; spackdir=$1; shift;;
            -no-extra-products)  opt_skip_extra_products=1;;
            -no-pull)            opt_no_pull=1;;
            -upstream)           eval $op1arg; upstreams+=($1); opt_use_cvmfs=0; shift;;
            -padding)            opt_padding=1;;
            -arch)               eval $op1arg; arch=$1; shift;;
            -host-arch)          opt_host_arch=1;;
            -no-kmod)            opt_no_kmod=1;;
            -no-view)            opt_no_view=1;;
            -no-use-cvmfs)       opt_use_cvmfs=0;;
            *)                   echo "Unknown option -$op"; do_help=1;;
        esac
    else
        aa=`echo "$1" | sed -e"s/'/'\"'\"'/g"` args="$args '$aa'"; shift
    fi
done
eval "set -- $args \"\$@\""; unset args aa

test -n "${do_help-}" -o $# -ge 2 && echo "$USAGE" && exit

if [ "x$SPACK_ROOT" == "x$spackdir" ]; then
  echo "Using pre-existing Spack installation $SPACK_ROOT.\nIf this is not correct, hit Ctrl-C and run 'unset SPACK_ROOT'."
  sleep 5
  spack env deactivate
fi

# JCF, 1/16/15
# Save all output from this script (stdout + stderr) in a file with a
# name that looks like "quick-start.sh_Fri_Jan_16_13:58:27.script" as
# well as all stderr in a file with a name that looks like
# "quick-start.sh_Fri_Jan_16_13:58:27_stderr.script"
alloutput_file=$( date | awk -v "SCRIPTNAME=$(basename $0)" '{print SCRIPTNAME"_"$1"_"$2"_"$3"_"$4".script"}' )
stderr_file=$( date | awk -v "SCRIPTNAME=$(basename $0)" '{print SCRIPTNAME"_"$1"_"$2"_"$3"_"$4"_stderr.script"}' )
mkdir -p $Base/qms-log
exec  > >(tee "$Base/qms-log/$alloutput_file")
exec 2> >(tee "$Base/qms-log/$stderr_file")

svariant=""
advariant=""

if [ -n "${squalifier-}" ]; then
    svariant="s=${squalifier}"
fi
if [ -n "${aqualifier-}" ]; then
    advariant="artdaq=${aqualifier}"
fi

view_opt=""
if [ $opt_no_view -eq 1 ];then
    view_opt="--without-view"
fi

build_system_script=`find $Base/srcs $Base -maxdepth 4 -type f -name setup_spack_build_system_v1.1.sh|head -1`
if [[ "x$build_system_script" == "x" ]];then
  echo "WARNING: setup_spack_build_system_v1.1.sh not found, downloading from https://github.com/art-daq/artdaq-demo"
  cd $Base
  wget https://raw.githubusercontent.com/art-daq/artdaq_demo/refs/heads/develop/tools/setup_spack_build_system_v1.1.sh
  build_system_script=$Base/setup_spack_build_system_v1.1.sh
fi

echo "63f733cce08e454534e24a9cfd95a64bd6e88ae9 *$build_system_script" | sha1sum -c -
if [ $? -ne 0 ]; then
  echo "ERROR: setup_spack_build_system_v1.1.sh does not have the expected checksum! Please check Github for updates to this script!"
  exit 1
fi

source $build_system_script
# Note that install_spack_build_system sources setup-env.sh
install_spack_build_system $Base $spackdir $opt_padding

if [[ $tag == "develop" ]] && [[ $opt_dev_only -eq 0 ]]; then
    tag=`spack list --format=version_json otsdaq-suite|jq ".[]|.latest_version"| sed -e 's/^"//' -e 's/"$//'`
fi

concrete_include_cmd=

os_long=$(spack arch -o)

if [ $opt_host_arch -eq 1 ]; then
    arch_opt=""
elif [[ "x$arch" != "x" ]]; then
    arch_opt="arch=$arch"
else
    arch_opt="arch=linux-${os_long}-x86_64_v3"
fi

os=$(echo ${os_long//./_}|sed 's/almalinux/al/;s/ubuntu/u/')
if [ $opt_use_cvmfs -eq 1 ] && [ -d /cvmfs/fermilab.opensciencegrid.org/products/artdaq/spack_v1.1 ]; then
  if [ $opt_dev_only -eq 1 ]; then
    ots=`ls -d /cvmfs/fermilab.opensciencegrid.org/products/artdaq/spack_v1.1/ots-*-${os}|tail -1`
    upstreams+=($ots)
  else
    artdaq=`ls -d /cvmfs/fermilab.opensciencegrid.org/products/artdaq/spack_v1.1/artdaq-*-${os}|tail -1`
    upstreams+=($artdaq)
  fi
fi

# If updating upstreams, clear existing file first
if [ ${#upstreams[@]} -gt 0 ]; then
  rm $spackdir/etc/spack/upstreams.yaml
fi
for upstream in ${upstreams[@]}; do
    for upstreamdir in `find $upstream -type f -wholename '*/.spack-db/index.json'|grep -v bootstrap 2>/dev/null`; do
        echo "Getting real directory for upstream database $upstreamdir"
        upstreamdir=`dirname $upstreamdir`
        upstreamdir=`dirname $upstreamdir`
        upstreamdir=`realpath $upstreamdir`
        upstreamname=`echo $upstreamdir|sed 's|/__spack[^/]*||g;s|/spack/opt/spack||g'`

        if ! [ -d $upstreamdir/.spack-db ]; then
            echo "No Spack instance found at $upstream!"
            continue
        fi

        if ! [ -f $spackdir/etc/spack/upstreams.yaml ]; then
            echo "upstreams:" > $spackdir/etc/spack/upstreams.yaml
        fi

        if [ `grep -c $upstreamdir $spackdir/etc/spack/upstreams.yaml` -eq 0 ]; then
            # Only add upstream if not already present
            echo "  upstream${upstreamname//\//-}:" >>$spackdir/etc/spack/upstreams.yaml
            echo "    install_tree: $upstreamdir" >>$spackdir/etc/spack/upstreams.yaml
        fi
    done

    # Get this upstream's upstreams
    if [ -f $upstream/spack/etc/spack/upstreams.yaml ]; then
        tail -n +2 $upstream/spack/etc/spack/upstreams.yaml >>$spackdir/etc/spack/upstreams.yaml
    fi

    for envdir in `find $upstream -type d -wholename '*/var/spack/environments' 2>/dev/null`; do
        echo "Looking for otsdaq environments in $envdir"

        environment="ots-${tag}-${os_long//./_}"
        if ! [ -d $environment ]; then continue; fi
        environment_dir=`realpath $environment`
        echo "Adding environment $environment_dir to include-concrete list"
        concrete_include_cmd="$concrete_include_cmd --include-concrete $environment_dir"
    done
done

spack reindex

BUILD_J=$((`cat /proc/cpuinfo|grep processor|tail -1|awk '{print $3}'` + 1))
env_name=ots-${tag}-${os}
gccver=13.4.0

if [ "x$gccver" != "x" ];then
    spack load --first gcc@${gccver} >/dev/null 2>&1
    if [ $? -ne 0 ];then
      spack install -j $BUILD_J gcc@${gccver} $arch_opt +binutils
      installStatus=$?
      spack load gcc@${gccver}
    fi
fi

spack compiler find

cd $Base

if [ ${opt_dev_only:-0} -eq 0 ];then
    spack env create ${concrete_include_cmd} $view_opt ${env_name}
    spack env activate ${env_name}
    ln -s ${spackdir}/var/spack/environments/${env_name}

    # OTS always wants to re-make the srcs link
    if ! [ -d srcs ];then
        rm srcs >/dev/null 2>&1
        ln -s $spackdir/var/spack/environments/${env_name} srcs
    fi

    if [ $opt_no_kmod -eq 1 ];then
        spack add trace~kmod
    else
        spack add trace+kmod
    fi

    spack add otsdaq-suite@${tag}+demo ${svariant} ${advariant} ${arch_opt}
    spack add otsdaq %gcc${gccver:+@${gccver}} # Ensure proper compiler is used
    env_to_activate=${env_name}
fi

function checkout_package()
{
    pkg=$1
    if ! [ -d $pkg ]; then
        if [ $opt_w -eq 0 ];then
            git clone https://github.com/art-daq/$pkg.git
        else
            git clone git@github.com:art-daq/$pkg.git
        fi
    else
        cd $pkg
        git pull
        cd ..
    fi
}

if [[ ${opt_develop:-0} -eq 1 ]];then
    env_to_activate="ots-develop"
    cd $Base
    rm srcs
    mkdir srcs
    cd srcs
    for pkg in otsdaq otsdaq-demo otsdaq-utilities otsdaq-components otsdaq-epics otsdaq-prepmodernization otsdaq-suite;do
        checkout_package $pkg
    done
    cd $Base
fi

    cat >setup_ots.sh <<-EOF
echo # This script is intended to be sourced.

if [ \${OTSDAQ_SETUP:-0} -eq 0 ]; then
  # Save environment
  declare -x >$Base/.env_before_setup_ots
fi

SCRIPT_DIR="\$( cd "\$( dirname "\${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
otsdir=\$SCRIPT_DIR

sh -c "[ \`ps \$\$ | grep bash | wc -l\` -gt 0 ] || { echo 'Please switch to the bash shell before running ots.'; exit; }" || exit

export BUILD_J=\$((\`cat /proc/cpuinfo|grep processor|tail -1|awk '{print \$3}'\` + 1))
export SPACK_DISABLE_LOCAL_CONFIG=true
export SPACK_USER_CACHE_PATH=$Base/.spack-cache
source $spackdir/share/spack/setup-env.sh

spack load --first gcc${gccver:+@${gccver}}
spack env activate ${env_to_activate}
pushd $Base
spack mpd select .
popd

#handle using ots-develop local install area
if [ -d \$SCRIPT_DIR/local/install ]; then
    export PATH=\$SCRIPT_DIR/local/install/bin:\$PATH
    export LD_LIBRARY_PATH=\$SCRIPT_DIR/local/install/lib:\$SCRIPT_DIR/local/install/lib64:\$LD_LIBRARY_PATH
    export CET_PLUGIN_PATH=\$SCRIPT_DIR/local/install/lib:\$CET_PLUGIN_PATH
    export ROOT_INCLUDE_PATH=\$SCRIPT_DIR/local/install/include:\$ROOT_INCLUDE_PATH

        export OTSDAQ_DIR=\${OTSDAQ_DIR:-\$SCRIPT_DIR/local/install} #only set if not set by spack, e.g. needed by UpdateOTS.sh
        export OTSDAQ_LIB=\${OTSDAQ_LIB:-\$SCRIPT_DIR/local/install/lib} #only set if not set by spack, e.g. needed by otsConfiguration_Wizard_CMake.xml, otsConfiguration_MacroMaker_CMake.xml
        export OTSDAQ_UTILITIES_LIB=\${OTSDAQ_UTILITIES_LIB:-\$SCRIPT_DIR/local/install/lib} #only set if not set by spack, needed by otsConfiguration_Wizard_CMake.xml, otsConfiguration_MacroMaker_CMake.xml
        export OTSDAQ_UTILITIES_DIR=\${OTSDAQ_UTILITIES_DIR:-\$SCRIPT_DIR/local/install}

        # in ots-develop mode, set WebPath because OTSDAQ_UTILITIES_DIR is not setup
        if [ -d \$SCRIPT_DIR/srcs/otsdaq-utilities/WebGUI ]; then
                export OTSDAQ_WEB_PATH=\$SCRIPT_DIR/srcs/otsdaq-utilities/WebGUI
        else
                export OTSDAQ_WEB_PATH=\$(readlink -f "\$OTSDAQ_UTILITIES_LIB/../WebGUI")
        fi
        export OTS_FILE_PARSE_PATTERN="/srcs/" #will be used to parse filename (i.e. for TRACE)

        export FHICL_FILE_PATH=\$SCRIPT_DIR/local/install/fcl:\$FHICL_FILE_PATH
        export MU2E_SEARCH_PATH=\$SCRIPT_DIR/local/install/share:\$MU2E_SEARCH_PATH

        export  ARTDAQ_DAQINTERFACE_DIR=\${ARTDAQ_DAQINTERFACE_DIR:-\$SCRIPT_DIR/local/install} #only set if not set by spack, e.g. needed by UpdateOTS.sh

fi
export ARTDAQ_DAQINTERFACE_VERSION="SPACK"
export ARTDAQ_PARTITION=1

k5user=\`klist|grep "Default principal"|cut -d: -f2|sed 's/@.*//;s/ //'\`
export TRACE_FILE=/tmp/trace_buffer_\$USER.\$k5user

export OTS_MAIN_PORT=2015

export USER_DATA="$Base/Data"
export ARTDAQ_DATABASE_URI="filesystemdb://$Base/databases/filesystemdb/test_db"
export OTSDAQ_DATA="$Base/Data/OutputData"
export OTS_SOURCE=$Base/srcs

echo -e "setup_ots.sh:\${LINENO} |  \t  Now your user data path is USER_DATA \t\t = \${USER_DATA}"
echo -e "setup_ots.sh:\${LINENO} |  \t  Now your database path is ARTDAQ_DATABASE_URI \t = \${ARTDAQ_DATABASE_URI}"
echo -e "setup_ots.sh:\${LINENO} |  \t  Now your output data path is OTSDAQ_DATA \t = \${OTSDAQ_DATA}"
echo

alias  kx='ots -k'
alias  mb='date; start_time=\$(date +%s); spack find | grep gcc; spack mpd build -j\$BUILD_J 2>&1 | sed s/__spack_path_placeholder__//g | sed s/\\\[padded-to-255-chars\\\]//g | sed s/\\\/tdaq-v......../\\\/tdaq-v_\ \ \ /g; end_time=\$(date +%s); spack mpd install; date; delta_time=\$((end_time - start_time)); fractional_minutes=\$(echo "scale=1; \$delta_time / 60" | bc); echo "Full time: \$delta_time seconds or \$fractional_minutes minutes"'
alias  ml='date; start_time=\$(date +%s); spack find | grep gcc; spack mpd build -j\$BUILD_J 2>&1 | sed s/__spack_path_placeholder__//g | sed s/\\\[padded-to-255-chars\\\]//g | sed s/\\\/tdaq-v......../\\\/tdaq-v_\ \ \ /g | tee m.txt; end_time=\$(date +%s); spack mpd install; date; delta_time=$((end_time - start_time)); fractional_minutes=\$(echo "scale=1; \$delta_time / 60" | bc); echo "Full time: \$delta_time seconds or \$fractional_minutes minutes"; less m.txt'
alias  mz='date; start_time=\$(date +%s); spack mpd z; spack mpd build --clean -j\$BUILD_J 2>&1 | sed s/__spack_path_placeholder__//g; end_time=\$(date +%s); spack mpd install; date; delta_time=\$((end_time - start_time)); fractional_minutes=\$(echo "scale=1; \$delta_time / 60" | bc); echo "Full time: \$delta_time seconds or \$fractional_minutes minutes"'

function mtidy() {
  base=$Base
  path=\`realpath --relative-to=\$base $1\`
  pushd \$base &>/dev/null
  if ! [ -d styleguide ]; then
    git clone https://github.com/art-daq/styleguide.git
  fi
  if [ `grep -c COMPILE_COMMANDS srcs/CMakeLists.txt` -eq 0 ]; then
    sed -i '/^project/a\set(CMAKE_EXPORT_COMPILE_COMMANDS ON)' srcs/CMakeLists.txt
    echo "Building to generate compile commands..."
    spack mpd build -G Ninja -j\$CETPKG_J &>/dev/null
  fi
  styleguide/cpplint/dune-cpp-style-check.sh build \$path
  popd &>/dev/null
}
function mlint() {
  base=$Base
  path=\`realpath --relative-to=\$base $1\`
  pushd \$base &>/dev/null
  if ! [ -d styleguide ]; then
    git clone https://github.com/art-daq/styleguide.git
  fi
  styleguide/cpplint/dunecpplint.sh \$path
  popd &>/dev/null
}

if [ \${OTSDAQ_SETUP:-0} -eq 0 ]; then
  # Now save a copy of the environment after setup
  declare -x >$Base/.env_after_setup_ots
  # Next, remove any variables that haven't changed
  grep -v -x -Ff $Base/.env_before_setup_ots $Base/.env_after_setup_ots >$Base/setup_ots_rte.sh
fi
export OTSDAQ_SETUP=1

echo
echo -e "setup_ots.sh:\${LINENO} |  \t  Now use 'ots --wiz' to configure otsdaq"
echo -e "setup_ots.sh:\${LINENO} |  \t   	Then use 'ots' to start otsdaq"
echo -e "setup_ots.sh:\${LINENO} |  \t   	Or use 'ots --help' for more options"
echo
echo -e "setup_ots.sh:\${LINENO} |  \t      use 'kx' to kill otsdaq processes"
echo

echo -e "setup_ots.sh:\${LINENO} |  \t  "
echo -e "setup_ots.sh:\${LINENO} |  \t      setup_ots.sh creates some compiling aliases for you:"
echo -e "setup_ots.sh:\${LINENO} |  \t     ---------------"
echo -e "setup_ots.sh:\${LINENO} |  \t            mb                             ### for incremental build"
echo -e "setup_ots.sh:\${LINENO} |  \t            mz                             ### for clean build"
echo -e "setup_ots.sh:\${LINENO} |  \t     ---------------"
echo -e "setup_ots.sh:\${LINENO} |  \t  "
echo -e "setup_ots.sh:\${LINENO} |  \t  "

EOF
#


########################################
########################################
## Setup USER_DATA and databases
########################################
########################################
cd $Base

# Fetch data and databases from develop
git clone https://github.com/art-daq/otsdaq_demo -b develop
if ! [ -d databases ]; then
    cp -a otsdaq_demo/NoGitDatabases databases
fi
if ! [ -d Data ];then
    cp -a otsdaq_demo/NoGitData Data
fi
rm -rf otsdaq_demo

export USER_DATA="$Base/Data"
export ARTDAQ_DATABASE_URI="filesystemdb://$Base/databases/filesystemdb/test_db"


#download get_tutorial_data script
wget https://raw.githubusercontent.com/art-daq/otsdaq_demo/develop/tools/get_tutorial_data.sh -O get_tutorial_data.sh --no-check-certificate

#change permissions so the script is executable
chmod 755 get_tutorial_data.sh

#execute script
./get_tutorial_data.sh


#copy tutorial launching scripts
echo
echo -e "UpdateOTS.sh [${LINENO}]  \t updating tutorial launch scripts..."
rm get_tutorial_data.sh &>/dev/null 2>&1 #hide output
rm reset_ots_tutorial.sh &>/dev/null 2>&1 #hide output
wget https://raw.githubusercontent.com/art-daq/otsdaq_demo/develop/tools/reset_ots_tutorial.sh -O reset_ots_tutorial.sh --no-check-certificate
chmod 755 reset_ots_tutorial.sh


########################################
########################################
## END Setup USER_DATA and databases
########################################
########################################


if [ ${opt_dev_only:-0} -eq 0 ];then
    spack concretize --force --deprecated && spack install --deprecated -j $BUILD_J
    installStatus=$?
fi
if [[ ${opt_develop:-0} -eq 1 ]];then
    spack env deactivate

    spack mpd init
    if [ ${opt_dev_only:-0} -eq 0 ];then
        spack mpd new-project --force -y --name ots-develop -C gcc${gccver:+@${gccver}} -E ${env_name} cxxstd=20 generator=ninja
    else
        spack mpd new-project --force -y --name ots-develop -C gcc${gccver:+@${gccver}} cxxstd=20 generator=ninja
    fi
    spack env activate ots-develop

    spack mpd build --clean -j $BUILD_J && spack mpd install
    installStatus=$?
    cd $Base
fi

if [ $installStatus -eq 0 ]; then
    echo "otsdaq-demo has been installed correctly. Use 'source setup_ots.sh' to setup your otsdaq software, then follow the instructions or visit the project redmine page for more info: https://github.com/art-daq/otsdaq/wiki"
    echo
    echo "In the future, when you open a new terminal, just use 'source setup_ots.sh' to setup your ots installation."
    echo
else
    echo "BUILD ERROR!!! SOMETHING IS VERY WRONG!!!"
    echo
    echo
fi

endtime=`date`

echo "Build start time: $starttime"
echo "Build end time:   $endtime"

exit $installStatus
