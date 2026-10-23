#! /bin/bash
# ots-quick-lite-start.sh
# Lightweight otsdaq install: only otsdaq, otsdaq-utilities, and otsdaq-demo
# (cloned read-only over HTTPS), with no Spack, CVMFS, xdaq, or artdaq dependence.
# Plain cmake + gcc. The cet suite (cetmodules, cetlib, fhicl-cpp, messagefacility)
# is built from source into local/install (~40s) and otsdaq is built against it.
# OTS_LITE=1 is exported here and in the generated setup_ots.sh so that
# both the build and the runtime know they are in lite mode.
# Derived from ots-quick-spack-start.sh (quick-mrb-start.sh - Eric Flumerfelt, May 20, 2016)

export OTS_LITE=1

git_status=`git status 2>/dev/null`
git_sts=$?
if [ $git_sts -eq 0 ];then
    echo "This script is designed to be run in a fresh install directory!"
    exit 1
fi

echo "$0 $@" >$PWD/ots-quick-lite-start.lastrun.sh

starttime=`date`
Base=$PWD
test -d log || mkdir log
test -d Data && rmdir Data
test -d databases && rmdir databases

env_opts_var=`basename $0 | sed 's/\.sh$//' | tr 'a-z-.' 'A-Z__'`_OPTS
USAGE="\
   usage: `basename $0` [options]
examples: `basename $0`
          `basename $0` --debug
          `basename $0` --branch feature/ots-lite --repo-base /path/to/dev-srcs
--debug       perform a debug build
--branch      Git branch to check out in srcs/ for the 3 lite repos (default: develop)
--repo-base   Where to clone the 3 repos from (default: https://github.com/art-daq;
              may be a local directory containing otsdaq, otsdaq-utilities, otsdaq-demo)
--no-pull     Do not git pull repos that are already checked out
--no-build    Only set up toolchain, deps, and sources; skip the otsdaq build
-v            Be more verbose
-x            set -x this script
"

# Process script arguments and options
eval env_opts=\${$env_opts_var-} # can be args too

branch=develop
repo_base=https://github.com/art-daq
build_type=Release
installStatus=0
eval "set -- $env_opts \"\$@\""
op1chr='rest=`expr "$op" : "[^-]\(.*\)"`   && set -- "-$rest" "$@"'
op1arg='rest=`expr "$op" : "[^-]\(.*\)"`   && set --  "$rest" "$@"'
reqarg="$op1arg;"'test -z "${1+1}" &&echo opt -$op requires arg. &&echo "$USAGE" &&exit'
args= do_help= opt_v=0; opt_no_pull=0; opt_no_build=0
while [ -n "${1-}" ];do
    if expr "x${1-}" : 'x-' >/dev/null;then
        op=`expr "x$1" : 'x-\(.*\)'`; shift   # done with $1
        leq=`expr "x$op" : 'x-[^=]*\(=\)'` lev=`expr "x$op" : 'x-[^=]*=\(.*\)'`
        test -n "$leq"&&eval "set -- \"\$lev\" \"\$@\""&&op=`expr "x$op" : 'x\([^=]*\)'`
        case "$op" in
            \?*|h*)              eval $op1chr; do_help=1;;
            v*)                  eval $op1chr; opt_v=`expr $opt_v + 1`;;
            x*)                  eval $op1chr; set -x;;
            -debug)              build_type=Debug;;
            -branch)             eval $reqarg; branch=$1; shift;;
            -repo-base)          eval $reqarg; repo_base=$1; shift;;
            -no-pull)            opt_no_pull=1;;
            -no-build)           opt_no_build=1;;
            *)                   echo "Unknown option -$op"; do_help=1;;
        esac
    else
        aa=`echo "$1" | sed -e"s/'/'\"'\"'/g"` args="$args '$aa'"; shift
    fi
done
eval "set -- $args \"\$@\""; unset args aa
# remembered so the mz_uc alias in setup_ots.sh can rerun this script with the same source options
lite_rerun_opts="--branch $branch --repo-base $repo_base"

test -n "${do_help-}" -o $# -ge 2 && echo "$USAGE" && exit

# JCF, 1/16/15
# Save all output from this script (stdout + stderr) in a file with a
# name that looks like "quick-start.sh_Fri_Jan_16_13:58:27.script" as
# well as all stderr in a file with a name that looks like
# "quick-start.sh_Fri_Jan_16_13:58:27_stderr.script"
alloutput_file=$( date | awk -v "SCRIPTNAME=$(basename $0)" '{print SCRIPTNAME"_"$1"_"$2"_"$3"_"$4".script"}' )
stderr_file=$( date | awk -v "SCRIPTNAME=$(basename $0)" '{print SCRIPTNAME"_"$1"_"$2"_"$3"_"$4"_stderr.script"}' )
mkdir -p $Base/qls-log
exec  > >(tee "$Base/qls-log/$alloutput_file")
exec 2> >(tee "$Base/qls-log/$stderr_file")

########################################
## Toolchain: gcc >= 12 (gcc-toolset-13 RPM on AL9) and cmake >= 3.24 (user-space download, no root)
########################################
if [ -f /opt/rh/gcc-toolset-13/enable ]; then
    source /opt/rh/gcc-toolset-13/enable
else
    echo "WARNING: /opt/rh/gcc-toolset-13 not found; using system $(g++ --version | head -1). cetlib needs gcc >= 12."
fi

cmake_ok=0
if command -v cmake >/dev/null 2>&1; then
    cmake_ver=$(cmake --version | head -1 | awk '{print $3}')
    [ "$(printf '%s\n3.24\n' "$cmake_ver" | sort -V | head -1)" = "3.24" ] && cmake_ok=1
fi
if [ $cmake_ok -eq 0 ]; then
    if ! [ -x $Base/cmake/bin/cmake ]; then
        echo "Downloading cmake 4.4.4 into $Base/cmake (user-space, no root)..."
        mkdir -p $Base/cmake
        curl -fsSL https://github.com/Kitware/CMake/releases/download/v4.4.4/cmake-4.4.4-linux-x86_64.tar.gz | tar xz -C $Base/cmake --strip-components=1
    fi
    export PATH=$Base/cmake/bin:$PATH
fi
echo "Using $(cmake --version | head -1) and $(g++ --version | head -1)"

########################################
## Prerequisite check: things that must come from the OS (need root to install).
## Report everything missing at once, with the exact install commands, then stop.
########################################
missing_rpm=(); missing_deb=(); fallback=()
need() { # need <probe file> <rpm name> <deb name>
    [ -e "$1" ] || { missing_rpm+=($2); missing_deb+=($3); }
}
need /usr/include/boost/version.hpp            boost-devel      libboost-all-dev
need /usr/include/sqlite3.h                    sqlite-devel     libsqlite3-dev
need /usr/include/tbb/tbb.h                    tbb-devel        libtbb-dev
need /usr/include/openssl/ssl.h                openssl-devel    libssl-dev
need /usr/include/curl/curl.h                  libcurl-devel    libcurl4-openssl-dev
need /usr/include/python3*/Python.h            python3-devel    python3-dev
for t in git curl tar make awk sed; do command -v $t >/dev/null 2>&1 || { missing_rpm+=($t); missing_deb+=($t); }; done
gccmajor=$(g++ -dumpversion 2>/dev/null | cut -d. -f1)
[ "${gccmajor:-0}" -ge 12 ] || { missing_rpm+=(gcc-toolset-13-gcc-c++); missing_deb+=(g++-13); }
# these two have a from-source fallback below, so only inform
[ -e /usr/include/xercesc/dom/DOM.hpp ] || fallback+=("xerces-c-devel (libxerces-c-dev)")
[ -e /usr/include/zmq.hpp ]              || fallback+=("cppzmq-devel (cppzmq-dev)")

if [ ${#fallback[@]} -gt 0 ]; then
    echo
    echo "NOTE: not found on this system, will be built from source into $prefix (slower; install with root to skip):"
    printf '      %s\n' "${fallback[@]}"
fi
if [ ${#missing_rpm[@]} -gt 0 ]; then
    echo
    echo "ERROR: required system packages are missing and cannot be built by this script. Install them as root, then rerun:"
    echo
    echo "   RHEL / AlmaLinux / Rocky:  sudo dnf install ${missing_rpm[*]}"
    echo "   Debian / Ubuntu:           sudo apt install ${missing_deb[*]}"
    echo
    exit 1
fi

BUILD_J=$((`cat /proc/cpuinfo|grep processor|tail -1|awk '{print $3}'` + 1))
prefix=$Base/local/install
mkdir -p $prefix

# Common cmake flags for cetmodules-based projects. cetmodules 4.x requires CetProvideDependency,
# and no longer auto-loads cet_make_library/cet_cmake_config (CetMake, CetCMakeConfig); projects
# written for cetmodules 3 (TRACE, most otsdaq subdirs) rely on them being preloaded.
cet_cmake_flags="-DCMAKE_BUILD_TYPE=$build_type -DCMAKE_CXX_STANDARD=20 -DCMAKE_INSTALL_PREFIX=$prefix -DCMAKE_PREFIX_PATH=$prefix -DCMAKE_PROJECT_TOP_LEVEL_INCLUDES:STRING=CetProvideDependency;CetMake;CetCMakeConfig -DBUILD_TESTING=OFF"
# same flags for use inside the generated setup_ots.sh aliases, where a bare ';' would end the command
cet_cmake_flags_alias="${cet_cmake_flags//;/\\;}"

function build_package()
{
    # build_package <name> <srcdir> [cmake flags...]
    name=$1; src=$2; shift 2
    s=$(date +%s)
    echo "########## building $name  $(date)"
    cmake -S $src -B $Base/build/$name "$@" \
      && cmake --build $Base/build/$name -j $BUILD_J \
      && cmake --install $Base/build/$name
    rc=$?
    printf "%-20s rc=%d  %4ds\n" $name $rc $(( $(date +%s) - s )) | tee -a $Base/build-timings.txt
    return $rc
}

########################################
## cet suite from source (~40s on 24 cores): cetmodules, cetlib-except, hep-concurrency, cetlib, fhicl-cpp, messagefacility
## then TRACE and artdaq-database (~50s), all into local/install
## Catch2 is only needed because messagefacility unconditionally builds its MF_catch_main test helper (upstream FIXME).
########################################
cd $Base
mkdir -p deps
cd deps
test -d Catch2 || git clone -q --depth 1 -b v3.8.1 https://github.com/catchorg/Catch2.git
test -d cetmodules || git clone -q https://github.com/FNALssi/cetmodules.git
for pkg in cetlib-except hep-concurrency cetlib fhicl-cpp messagefacility; do
    test -d $pkg || git clone -q https://github.com/art-framework-suite/$pkg.git
done
test -d trace || git clone -q https://github.com/art-daq/trace.git
test -d artdaq_database || git clone -q -b feature/ots-lite https://github.com/art-daq/artdaq-database.git artdaq_database
# artdaq-database reads fhicl::extended_value::raw_value, which upstream fhicl-cpp does not have.
# Apply the same patch the fhicl-cpp+db Spack variant uses (art-daq/artdaq-spack); idempotent on rerun.
fhicl_patch_url=https://raw.githubusercontent.com/art-daq/artdaq-spack/cb888fa56a2584d170e7fff04c57edc0c48eaf0b/packages/fhicl-cpp/fhicl-cpp-v4_19_02.patch
if ! grep -q raw_value fhicl-cpp/fhiclcpp/extended_value.h; then
    curl -fsSL $fhicl_patch_url -o fhicl-cpp-db.patch || { echo "ERROR: cannot download fhicl-cpp patch $fhicl_patch_url"; exit 1; }
    git -C fhicl-cpp apply $Base/deps/fhicl-cpp-db.patch || { echo "ERROR: fhicl-cpp patch did not apply (fhicl-cpp develop moved?)"; exit 1; }
fi
cd $Base
: > $Base/build-timings.txt
build_package Catch2 $Base/deps/Catch2 -DCMAKE_BUILD_TYPE=$build_type -DCMAKE_CXX_STANDARD=20 -DCMAKE_INSTALL_PREFIX=$prefix -DBUILD_TESTING=OFF || exit 1

########################################
## System libraries otsdaq needs: use the OS copy if present, otherwise build from source (no root needed).
## Boost, SQLite, TBB, OpenSSL, libcurl, Python are large and expected from the OS (see readme).
########################################
plain_flags="-DCMAKE_BUILD_TYPE=$build_type -DCMAKE_INSTALL_PREFIX=$prefix -DCMAKE_PREFIX_PATH=$prefix -DBUILD_TESTING=OFF"
# xerces-c (XML parser used by the otsdaq configuration layer)
if ! [ -f /usr/include/xercesc/dom/DOM.hpp ] && ! [ -f $prefix/include/xercesc/dom/DOM.hpp ]; then
    echo "xerces-c-devel not found on system; building xerces-c from source..."
    cd $Base/deps
    test -d xerces-c || git clone -q --depth 1 -b v3.3.0 https://github.com/apache/xerces-c.git
    cd $Base
    build_package xerces-c $Base/deps/xerces-c $plain_flags -Dnetwork=OFF || exit 1
fi
# zeromq + cppzmq (FE -> Supervisor publish/subscribe in CoreSupervisors)
if ! [ -f /usr/include/zmq.hpp ] && ! [ -f $prefix/include/zmq.hpp ]; then
    echo "cppzmq-devel not found on system; building libzmq and cppzmq from source..."
    cd $Base/deps
    test -d libzmq || git clone -q --depth 1 -b v4.3.5 https://github.com/zeromq/libzmq.git
    test -d cppzmq || git clone -q --depth 1 -b v4.10.0 https://github.com/zeromq/cppzmq.git
    cd $Base
    if ! [ -f /usr/include/zmq.h ] && ! [ -f $prefix/include/zmq.h ]; then
        # libzmq 4.3.5 declares cmake_minimum_required 3.0.2, which cmake 4.x refuses without this
        build_package libzmq $Base/deps/libzmq $plain_flags -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DWITH_PERF_TOOL=OFF -DZMQ_BUILD_TESTS=OFF || exit 1
    fi
    build_package cppzmq $Base/deps/cppzmq $plain_flags -DCPPZMQ_BUILD_TESTS=OFF || exit 1
fi

for pkg in cetmodules cetlib-except hep-concurrency cetlib fhicl-cpp messagefacility; do
    build_package $pkg $Base/deps/$pkg $cet_cmake_flags || exit 1
done
# TRACE (otsdaq::Macros links TRACE::MF); no kernel module in lite
build_package trace $Base/deps/trace $cet_cmake_flags -DWANT_KMOD=OFF || exit 1
# artdaq-database: the real "Database" configuration plugin (filesystemdb read/write); no MongoDB driver needed
build_package artdaq_database $Base/deps/artdaq_database $cet_cmake_flags -DWITH_MONGODB=OFF || exit 1

########################################
## Checkout the 3 lite repos (read-only; --repo-base may be a local directory while iterating)
########################################
function checkout_package()
{
    pkg=$1
    if ! [ -d $pkg ]; then
        git clone $repo_base/$pkg
        git -C $pkg checkout $branch
    elif [ $opt_no_pull -eq 0 ]; then
        cd $pkg
        git checkout $branch
        git pull
        cd ..
    fi
}

cd $Base
test -L srcs && rm srcs
mkdir -p srcs
cd srcs
for pkg in otsdaq otsdaq-utilities otsdaq-demo;do
    checkout_package $pkg
done
cd $Base

    cat >setup_ots.sh <<-EOF
echo # This script is intended to be sourced.

SCRIPT_DIR="\$( cd "\$( dirname "\${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
otsdir=\$SCRIPT_DIR

sh -c "[ \`ps \$\$ | grep bash | wc -l\` -gt 0 ] || { echo 'Please switch to the bash shell before running ots.'; exit; }" || exit

export BUILD_J=\$((\`cat /proc/cpuinfo|grep processor|tail -1|awk '{print \$3}'\` + 1))
export OTS_LITE=1
[ -f /opt/rh/gcc-toolset-13/enable ] && source /opt/rh/gcc-toolset-13/enable
[ -x $Base/cmake/bin/cmake ] && export PATH=$Base/cmake/bin:\$PATH
export BUILD_J=\$((\`cat /proc/cpuinfo|grep processor|tail -1|awk '{print \$3}'\` + 1))

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
alias  mb='date; start_time=\$(date +%s); for p in otsdaq otsdaq-utilities otsdaq-demo; do cmake --build $Base/build/\$p -j\$BUILD_J && cmake --install $Base/build/\$p || break; done; end_time=\$(date +%s); date; echo "Full time: \$((end_time - start_time)) seconds"'
alias  mz='date; start_time=\$(date +%s); for p in otsdaq otsdaq-utilities otsdaq-demo; do rm -rf $Base/build/\$p; cmake -S $Base/srcs/\$p -B $Base/build/\$p $cet_cmake_flags_alias && cmake --build $Base/build/\$p -j\$BUILD_J && cmake --install $Base/build/\$p || break; done; end_time=\$(date +%s); date; echo "Full time: \$((end_time - start_time)) seconds"'
# ultra clean: wipe build/ and local/install, rebuild deps and otsdaq from scratch (re-evaluates all dependencies, like spack concretize)
alias  mz_uc='date; start_time=\$(date +%s); rm -rf $Base/build $Base/local/install $Base/build-timings.txt; (cd $Base && ./$(basename "${BASH_SOURCE[0]}") --no-pull $lite_rerun_opts); end_time=\$(date +%s); date; echo "Full time: \$((end_time - start_time)) seconds"'

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
echo -e "setup_ots.sh:\${LINENO} |  \t            mz_uc                          ### for ultra clean build (also rebuilds dependencies)"
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

#execute script (it checks for setup_ots.sh in $PWD, so it must run from $Base); then tuck its
#script_log/ under qls-log/ so the top level keeps only user-facing entries (setup_ots.sh, srcs/, ...)
./get_tutorial_data.sh
rm -rf $Base/qls-log/script_log; mv $Base/script_log $Base/qls-log/ 2>/dev/null


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


########################################
## Build otsdaq, otsdaq-utilities, otsdaq-demo against local/install (OTS_LITE is exported at the top)
########################################
if [ $opt_no_build -eq 0 ]; then
    cd $Base
    export OTS_SOURCE=$Base/srcs
    for pkg in otsdaq otsdaq-utilities otsdaq-demo; do
        build_package $pkg $Base/srcs/$pkg $cet_cmake_flags
        installStatus=$?
        if [ $installStatus -ne 0 ]; then
            echo "ERROR: build of $pkg failed (full log in $Base/qls-log/)"
            break
        fi
    done
fi

echo
echo "=== build timings:"
cat $Base/build-timings.txt
echo

if [ $installStatus -eq 0 ]; then
    echo "otsdaq lite has been installed correctly. Use 'source setup_ots.sh' to setup your otsdaq software."
    echo
    echo "In the future, when you open a new terminal, just use 'source setup_ots.sh' to setup your ots installation."
    echo
    echo "For tutorials and additional resources, go to https://otsdaq.fnal.gov"
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
