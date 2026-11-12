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

# macOS (native, Apple clang + Homebrew): everything Mac-specific below is guarded by is_mac,
# so Linux behaviour is unchanged. macOS ships bash 3.2, which lacks associative arrays used
# below; rerun under Homebrew's bash if it is there, otherwise say exactly how to get it.
is_mac=0
[ "$(uname -s)" = Darwin ] && is_mac=1
if [ $is_mac -eq 1 ] && [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
    for b in /opt/homebrew/bin/bash /usr/local/bin/bash; do
        [ -x $b ] && exec $b "$0" "$@"
    done
    echo "ERROR: this script needs bash 4 or newer; macOS has bash ${BASH_VERSION}."
    if ! command -v brew >/dev/null 2>&1; then
        echo "       Install Homebrew (https://brew.sh) by pasting this into Terminal:"
        echo
        echo '   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
        echo
        echo "       then follow the 'Next steps' it prints, and run:"
    else
        echo "       Run:"
    fi
    echo
    echo "   brew install bash"
    echo
    echo "       then rerun the same command you used."
    exit 1
fi

git_status=`git status 2>/dev/null`
git_sts=$?
if [ $git_sts -eq 0 ];then
    echo "This script is designed to be run in a fresh install directory!"
    exit 1
fi

starttime=`date`
Base=$PWD
test -d tmp || mkdir tmp

echo "$0 $@" >$Base/tmp/ots-quick-lite-start.lastrun.sh
test -d Data && rmdir Data
test -d databases && rmdir databases

env_opts_var=`basename $0 | sed 's/\.sh$//' | tr 'a-z-.' 'A-Z__'`_OPTS
USAGE="\
   usage: `basename $0` [options]
examples: `basename $0`
          `basename $0` --debug
          `basename $0` --branch my-feature-branch --repo-base /path/to/dev-srcs
--debug       perform a debug build
--branch      Git branch to check out in srcs/ for the 3 lite repos (default: develop)
--repo-base   Where to clone the 4 repos from (default: https://github.com/art-daq;
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
mkdir -p $Base/tmp
exec  > >(tee "$Base/tmp/$alloutput_file")
exec 2> >(tee "$Base/tmp/$stderr_file")
# fixed name for the latest run's full output, so it can be found without knowing the date
ln -sf "$alloutput_file" "$Base/tmp/install.log"

########################################
## Toolchain: gcc >= 12 (gcc-toolset-13 RPM on AL9) and cmake >= 3.29 (user-space download, no root)
## (3.29 is where CMAKE_PROJECT_TOP_LEVEL_INCLUDES accepts module names, which cet_cmake_flags relies on)
########################################
brew_prefix=
if [ $is_mac -eq 1 ]; then
    # Apple clang from the Xcode Command Line Tools (g++ is clang on macOS); libraries from Homebrew
    command -v brew >/dev/null 2>&1 && brew_prefix=$(brew --prefix)
elif [ -f /opt/rh/gcc-toolset-13/enable ]; then
    source /opt/rh/gcc-toolset-13/enable
else
    echo "WARNING: /opt/rh/gcc-toolset-13 not found; using system $(g++ --version | head -1). cetlib needs gcc >= 12."
fi

cmake_ok=0
if command -v cmake >/dev/null 2>&1; then
    cmake_ver=$(cmake --version | head -1 | awk '{print $3}')
    [ "$(printf '%s\n3.29\n' "$cmake_ver" | sort -V | head -1)" = "3.29" ] && cmake_ok=1
fi
if [ $cmake_ok -eq 0 ] && [ $is_mac -eq 1 ]; then
    : # on macOS cmake comes from Homebrew; reported with the other missing packages below
elif [ $cmake_ok -eq 0 ]; then
    if ! [ -x $Base/cmake/bin/cmake ]; then
        case "$(uname -m)" in
            x86_64)  cmake_arch=linux-x86_64;;
            aarch64) cmake_arch=linux-aarch64;;
            *) echo "ERROR: cmake >= 3.29 not found and Kitware has no prebuilt cmake for $(uname -m). Install cmake >= 3.29 and rerun."; exit 1;;
        esac
        echo "Downloading cmake 4.4.4 ($cmake_arch) into $Base/cmake (user-space, no root)..."
        mkdir -p $Base/cmake
        curl -fsSL -o $Base/tmp/cmake.tar.gz https://github.com/Kitware/CMake/releases/download/v4.4.4/cmake-4.4.4-$cmake_arch.tar.gz \
          && tar xzf $Base/tmp/cmake.tar.gz -C $Base/cmake --strip-components=1 \
          || { echo "ERROR: cmake download/extract failed. Install cmake >= 3.29 and rerun."; exit 1; }
        rm -f $Base/tmp/cmake.tar.gz
    fi
    export PATH=$Base/cmake/bin:$PATH
fi
if [ $cmake_ok -eq 1 ] || command -v cmake >/dev/null 2>&1; then
    echo "Using $(cmake --version | head -1) and $(g++ --version 2>/dev/null | head -1)"
fi

########################################
## Prerequisite check: things that must come from the OS (need root to install).
## Report everything missing at once, with the exact install commands, then stop.
########################################
missing_rpm=(); missing_deb=(); missing_brew=(); fallback=(); mac_no_clt=0; mac_no_brew=0
if [ $is_mac -eq 1 ]; then
    # Apple clang comes with the Xcode Command Line Tools; without them g++/clang/git/make are stubs
    xcode-select -p >/dev/null 2>&1 || mac_no_clt=1
    [ -n "$brew_prefix" ] || mac_no_brew=1
    [ $cmake_ok -eq 1 ] || missing_brew+=(cmake)
fi
have_cxx() { [ $is_mac -eq 1 ] && [ $mac_no_clt -eq 1 ] && return 1; command -v g++ >/dev/null 2>&1; }
need() { # need <header> <rpm name> <deb name> <brew formula>: probe the compiler's include path (Debian
         # multiarch keeps e.g. curl/curl.h under /usr/include/<triplet>/), fall back to /usr/include if no g++ yet.
         # On macOS Homebrew headers are not on the default path; keg-only formulae (openssl@3) live under opt/.
    local inc=
    [ -n "$brew_prefix" ] && inc="-I$brew_prefix/include -I$brew_prefix/opt/$4/include"
    if have_cxx; then
        echo "#include <$1>" | g++ $inc -E -x c++ - -o /dev/null >/dev/null 2>&1 && return
    elif [ -e "/usr/include/$1" ]; then
        return
    fi
    missing_rpm+=($2); missing_deb+=($3); missing_brew+=($4)
}
need boost/version.hpp            boost-devel      libboost-all-dev        boost
need sqlite3.h                    sqlite-devel     libsqlite3-dev          sqlite
need tbb/tbb.h                    tbb-devel        libtbb-dev              tbb
need openssl/ssl.h                openssl-devel    libssl-dev              openssl@3
need curl/curl.h                  libcurl-devel    libcurl4-openssl-dev    curl
if [ $is_mac -eq 1 ]; then
    # Python's headers are found by the CMake probe below (Homebrew python or the CLT framework)
    for t in git curl tar make awk sed; do command -v $t >/dev/null 2>&1 || missing_brew+=($t); done
    command -v envsubst >/dev/null 2>&1 || missing_brew+=(gettext)   # used at run time by `ots`
else
ls /usr/include/python3*/Python.h >/dev/null 2>&1 || { missing_rpm+=(python3-devel); missing_deb+=(python3-dev); }
for t in git curl wget tar make awk sed; do command -v $t >/dev/null 2>&1 || { missing_rpm+=($t); missing_deb+=($t); }; done
# used at run time by the `ots` script, not by this installer
command -v envsubst >/dev/null 2>&1 || { missing_rpm+=(gettext); missing_deb+=(gettext-base); }
command -v killall  >/dev/null 2>&1 || { missing_rpm+=(psmisc);  missing_deb+=(psmisc); }
gccmajor=$(g++ -dumpversion 2>/dev/null | cut -d. -f1)
[ "${gccmajor:-0}" -ge 12 ] || { missing_rpm+=(gcc-toolset-13-gcc-c++); missing_deb+=(g++-13); }
fi

# Every system package the build needs, found the way the build finds it: configure a tiny probe
# project with the same policy range as cetmodules' find_package wrapper (under which CMake's own
# FindBoost is disabled, so BoostConfig.cmake is required). The compiler can see headers CMake
# cannot (e.g. CPATH from another environment), so the header checks above are not enough.
# PROBE_MISSING = must come from the OS; PROBE_FALLBACK = built from source below if absent.
prefix=$Base/local/install
probe=$Base/tmp/prereq_probe
build_xerces=0; build_zmq=0; probe_ran=0; probe_missing=()
# macOS: Homebrew's openssl@3 and sqlite are keg-only (not linked into $brew_prefix), so name them
mac_cmake_flags=
[ -n "$brew_prefix" ] && mac_cmake_flags="-DOPENSSL_ROOT_DIR=$brew_prefix/opt/openssl@3 -DSQLite3_ROOT=$brew_prefix/opt/sqlite"
if have_cxx && command -v cmake >/dev/null 2>&1; then
    rm -rf $probe; mkdir -p $probe
    cat > $probe/CMakeLists.txt <<'PROBE'
cmake_minimum_required(VERSION 3.24...4.1)
project(prereq_probe LANGUAGES CXX)
macro(probe name found kind)
  if(${found})
    message(STATUS "PROBE_OK ${name}")
  else()
    message(STATUS "PROBE_${kind} ${name}")
  endif()
endmacro()
find_package(Boost CONFIG QUIET COMPONENTS date_time filesystem program_options regex system thread unit_test_framework)
probe(Boost Boost_FOUND MISSING)
find_package(TBB CONFIG QUIET)
probe(TBB TBB_FOUND MISSING)
find_package(SQLite3 QUIET)
probe(SQLite3 SQLite3_FOUND MISSING)
find_package(OpenSSL QUIET)
probe(OpenSSL OpenSSL_FOUND MISSING)
find_package(CURL QUIET)
probe(CURL CURL_FOUND MISSING)
find_package(Threads QUIET)
probe(Threads Threads_FOUND MISSING)
find_package(Python 3.6 QUIET COMPONENTS Development.Embed)
probe(Python Python_FOUND MISSING)
find_package(XercesC 3.2 QUIET)
probe(XercesC XercesC_FOUND FALLBACK)
find_package(cppzmq CONFIG QUIET)
probe(cppzmq cppzmq_FOUND FALLBACK)
PROBE
    cmake -S $probe -B $probe/build -DCMAKE_PREFIX_PATH=$prefix $mac_cmake_flags > $probe/probe.log 2>&1
    if grep -q "PROBE_OK\|PROBE_MISSING\|PROBE_FALLBACK" $probe/probe.log; then
        probe_ran=1
        probe_missing=($(sed -n 's/.*PROBE_MISSING \([A-Za-z0-9]*\).*/\1/p' $probe/probe.log))
        grep -q "PROBE_FALLBACK XercesC" $probe/probe.log && { build_xerces=1; fallback+=("xerces-c-devel (libxerces-c-dev)"); }
        grep -q "PROBE_FALLBACK cppzmq"  $probe/probe.log && { build_zmq=1;    fallback+=("cppzmq-devel (cppzmq-dev)"); }
    fi
fi
if [ $probe_ran -eq 0 ]; then  # no compiler yet: decide the source builds by header, recheck on rerun
    [ -e /usr/include/xercesc/dom/DOM.hpp ] || [ -e $prefix/include/xercesc/dom/DOM.hpp ] || { build_xerces=1; fallback+=("xerces-c-devel (libxerces-c-dev)"); }
    [ -e /usr/include/zmq.hpp ] || [ -e $prefix/include/zmq.hpp ] || { build_zmq=1; fallback+=("cppzmq-devel (cppzmq-dev)"); }
fi

# OS package that provides each CMake package (RHEL family / Debian family)
declare -A pkg_rpm=([Boost]=boost-devel [TBB]=tbb-devel [SQLite3]=sqlite-devel [OpenSSL]=openssl-devel
                    [CURL]=libcurl-devel [Threads]=glibc-devel [Python]=python3-devel)
declare -A pkg_deb=([Boost]=libboost-all-dev [TBB]=libtbb-dev [SQLite3]=libsqlite3-dev [OpenSSL]=libssl-dev
                    [CURL]=libcurl4-openssl-dev [Threads]=libc6-dev [Python]=python3-dev)
declare -A pkg_brew=([Boost]=boost [TBB]=tbb [SQLite3]=sqlite [OpenSSL]=openssl@3
                     [CURL]=curl [Threads]= [Python]=python)
os_family=both
if [ $is_mac -eq 1 ]; then
    os_family=brew
elif [ -r /etc/os-release ]; then
    os_ids=$(. /etc/os-release; echo "$ID $ID_LIKE")
    case " $os_ids " in
        *" rhel "*|*" fedora "*|*" centos "*|*" almalinux "*|*" rocky "*) os_family=rpm;;
        *" debian "*|*" ubuntu "*) os_family=deb;;
    esac
fi
pkg_installed() {  # pkg_installed <rpm name> <deb name> <brew formula>
    case $os_family in
        rpm)  rpm -q "$1" >/dev/null 2>&1;;
        deb)  dpkg-query -W -f='${Status}' "$2" 2>/dev/null | grep -q "install ok installed";;
        brew) [ -n "$3" ] && brew list --versions "$3" >/dev/null 2>&1;;
        *)    return 1;;
    esac
}
installed_but_unseen=()
for name in "${probe_missing[@]}"; do
    if pkg_installed "${pkg_rpm[$name]}" "${pkg_deb[$name]}" "${pkg_brew[$name]}"; then
        installed_but_unseen+=($name)
    else
        missing_rpm+=(${pkg_rpm[$name]}); missing_deb+=(${pkg_deb[$name]}); missing_brew+=(${pkg_brew[$name]})
    fi
done
missing_rpm=($(printf '%s\n' "${missing_rpm[@]}" | awk 'NF && !seen[$0]++'))
missing_deb=($(printf '%s\n' "${missing_deb[@]}" | awk 'NF && !seen[$0]++'))
missing_brew=($(printf '%s\n' "${missing_brew[@]}" | awk 'NF && !seen[$0]++'))
# the list that decides whether we can continue, for this OS
if [ $is_mac -eq 1 ]; then n_missing=$(( ${#missing_brew[@]} + mac_no_clt + mac_no_brew )); else n_missing=${#missing_rpm[@]}; fi

if [ ${#fallback[@]} -gt 0 ]; then
    echo
    if [ $is_mac -eq 1 ]; then
        echo "NOTE: not found on this Mac, will be built from source into $prefix (slower). To skip that, run:"
        echo
        echo "   brew install$(printf '%s\n' "${fallback[@]}" | grep -q xerces && echo ' xerces-c')$(printf '%s\n' "${fallback[@]}" | grep -q zmq && echo ' zeromq cppzmq')"
    else
    echo "NOTE: not found on this system, will be built from source into $prefix (slower; install with root to skip):"
    printf '      %s\n' "${fallback[@]}"
    fi
fi
if [ ${#installed_but_unseen[@]} -gt 0 ]; then
    echo
    for name in "${installed_but_unseen[@]}"; do
        p=${pkg_rpm[$name]}; [ $os_family = deb ] && p=${pkg_deb[$name]}; [ $os_family = brew ] && p=${pkg_brew[$name]}
        echo "ERROR: $p is installed, but CMake still cannot find $name."
    done
    echo "       Installing it again will not help. Usually an environment variable points CMake or the"
    echo "       compiler at another copy. These are set in this shell:"
    set_vars=$(env | grep -E '^(CMAKE_PREFIX_PATH|CMAKE_MODULE_PATH|Boost_DIR|BOOST_ROOT|BOOSTROOT|TBB_DIR|TBBROOT|Python_ROOT_DIR|PYTHONHOME|CPATH|CPLUS_INCLUDE_PATH|LIBRARY_PATH|SPACK_ROOT)=' | cut -c1-150)
    if [ -n "$set_vars" ]; then
        echo "$set_vars" | sed 's/^/         /'
        echo "       Open a new shell without them (e.g. no Spack/UPS setup), or run:"
        echo "         unset $(echo "$set_vars" | cut -d= -f1 | tr '\n' ' ')"
        echo "       then rerun this script."
    else
        echo "         (none of the usual ones)"
        echo "       Send $probe/probe.log to the otsdaq developers."
    fi
    echo "       CMake's own message is in $probe/probe.log"
fi
if [ $is_mac -eq 1 ] && [ $n_missing -gt 0 ]; then
    echo
    echo "ERROR: required software is missing on this Mac. Run these in Terminal, in this order"
    echo "       (no administrator account needed beyond what macOS itself asks for),"
    echo "       then rerun the same command you used:"
    echo
    step=1
    if [ $mac_no_clt -eq 1 ]; then
        echo "   $step. Apple's command line tools (compiler, git, make); click Install in the window that opens:"
        echo
        echo "      xcode-select --install"
        echo
        step=$((step+1))
    fi
    if [ $mac_no_brew -eq 1 ]; then
        echo "   $step. Homebrew (https://brew.sh); afterwards run the 'Next steps' commands it prints:"
        echo
        echo '      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
        echo
        step=$((step+1))
    fi
    if [ ${#missing_brew[@]} -gt 0 ]; then
        echo "   $step. The libraries and tools otsdaq builds against:"
        echo
        echo "      brew install ${missing_brew[*]}"
        echo
    fi
    [ $probe_ran -eq 0 ] && { echo "   (Some checks need the compiler and cmake; rerunning after the installs checks the rest.)"; echo; }
elif [ ${#missing_rpm[@]} -gt 0 ]; then
    echo
    echo "ERROR: required system packages are missing and cannot be built by this script."
    echo "       Ask an administrator (root) to run this, then rerun the same command you used:"
    echo
    case $os_family in
        rpm) echo "   sudo dnf install ${missing_rpm[*]}"
             echo
             echo "   If dnf answers \"No match for argument\", enable the CRB and EPEL repositories first:"
             echo "   sudo dnf config-manager --set-enabled crb && sudo dnf install epel-release";;
        deb) echo "   sudo apt install ${missing_deb[*]}";;
        *)   echo "   RHEL / AlmaLinux / Rocky:  sudo dnf install ${missing_rpm[*]}"
             echo "   Debian / Ubuntu:           sudo apt install ${missing_deb[*]}";;
    esac
    [ $probe_ran -eq 0 ] && { echo; echo "   (Some checks need a C++ compiler; rerunning after the install checks the rest.)"; }
    echo
fi
[ $n_missing -gt 0 ] || [ ${#installed_but_unseen[@]} -gt 0 ] && exit 1
[ $is_mac -eq 1 ] && echo "Prerequisites: all found (Xcode Command Line Tools, Homebrew $brew_prefix, cmake, boost, tbb, sqlite, openssl@3, curl, python)."

if [ $is_mac -eq 1 ]; then
    BUILD_J=$(( $(sysctl -n hw.ncpu) + 1 ))
else
BUILD_J=$((`cat /proc/cpuinfo|grep processor|tail -1|awk '{print $3}'` + 1))
fi
prefix=$Base/local/install
mkdir -p $prefix

# Common cmake flags for cetmodules-based projects. cetmodules 4.x requires CetProvideDependency,
# and no longer auto-loads cet_make_library/cet_cmake_config (CetMake, CetCMakeConfig); projects
# written for cetmodules 3 (TRACE, most otsdaq subdirs) rely on them being preloaded.
cet_cmake_flags="-DCMAKE_BUILD_TYPE=$build_type -DCMAKE_CXX_STANDARD=20 -DCMAKE_INSTALL_PREFIX=$prefix -DCMAKE_PREFIX_PATH=$prefix -DCMAKE_PROJECT_TOP_LEVEL_INCLUDES:STRING=CetProvideDependency;CetMake;CetCMakeConfig -DBUILD_TESTING=OFF"
# same flags for use inside the generated setup_ots.sh aliases, where a bare ';' would end the command
cet_cmake_flags_alias="${cet_cmake_flags//;/\\;}"
if [ $is_mac -eq 1 ]; then  # keg-only Homebrew packages (see the prerequisite probe)
    cet_cmake_flags="$cet_cmake_flags $mac_cmake_flags"
    cet_cmake_flags_alias="$cet_cmake_flags_alias $mac_cmake_flags"
fi

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
    printf "%-20s rc=%d  %4ds\n" $name $rc $(( $(date +%s) - s )) | tee -a $Base/tmp/build-timings.txt
    return $rc
}

function ots_discover_repos()
{
    # ots_discover_repos <srcs dir>: the otsdaq repos to build, one per line, in build order.
    # otsdaq and the three standard repos come first (in that order); any other
    # srcs/otsdaq-*/ directory with a CMakeLists.txt (e.g. an experiment repo such as
    # otsdaq-td-ims-asic) follows, alphabetically, so it builds after otsdaq.
    local srcs=$1 known="otsdaq otsdaq-components otsdaq-utilities otsdaq-demo" r d
    for r in $known; do
        [ -f $srcs/$r/CMakeLists.txt ] && echo $r
    done
    for d in $srcs/otsdaq-*/; do
        r=$(basename $d)
        case " $known " in *" $r "*) continue;; esac
        [ -f $d/CMakeLists.txt ] && echo $r
    done
    return 0
}

########################################
## cet suite from source (~40s on 24 cores): cetmodules, cetlib-except, hep-concurrency, cetlib, fhicl-cpp, messagefacility
## then TRACE and artdaq-database (~50s), all into local/install
## Catch2 is only needed because messagefacility unconditionally builds its MF_catch_main test helper (upstream FIXME).
########################################
# clone_dep <dir> <url> [git clone options]: clone once; stop with a clear message if the clone
# fails (and remove a partial directory, so a rerun retries instead of building an empty tree)
clone_dep() {
    local dir=$1 url=$2; shift 2
    [ -d "$dir/.git" ] && return 0
    rm -rf "$dir"
    git clone -q "$@" "$url" "$dir" || { rm -rf "$dir"; echo "ERROR: git clone $* $url failed (network, or the branch/tag no longer exists)."; exit 1; }
}
cd $Base
mkdir -p deps
cd deps
clone_dep Catch2 https://github.com/catchorg/Catch2.git --depth 1 -b v3.8.1
clone_dep cetmodules https://github.com/FNALssi/cetmodules.git
for pkg in cetlib-except hep-concurrency cetlib fhicl-cpp messagefacility; do
    clone_dep $pkg https://github.com/art-framework-suite/$pkg.git
done
clone_dep trace https://github.com/art-daq/trace.git
# artdaq-database: the branch named by --branch if that repo has one (coordinated feature work),
# otherwise develop, which has the lite support (feature/ots-lite was merged and deleted)
adb_url=https://github.com/art-daq/artdaq-database.git
if git ls-remote --exit-code --heads $adb_url "$branch" >/dev/null 2>&1; then adb_branch=$branch; else adb_branch=develop; fi
[ -d artdaq_database/.git ] || echo "artdaq-database: using branch $adb_branch"
clone_dep artdaq_database $adb_url -b $adb_branch
# artdaq-database reads fhicl::extended_value::raw_value, which upstream fhicl-cpp does not have.
# Apply the same patch the fhicl-cpp+db Spack variant uses (art-daq/artdaq-spack); idempotent on rerun.
fhicl_patch_url=https://raw.githubusercontent.com/art-daq/artdaq-spack/cb888fa56a2584d170e7fff04c57edc0c48eaf0b/packages/fhicl-cpp/fhicl-cpp-v4_19_02.patch
if ! grep -q raw_value fhicl-cpp/fhiclcpp/extended_value.h; then
    curl -fsSL $fhicl_patch_url -o fhicl-cpp-db.patch || { echo "ERROR: cannot download fhicl-cpp patch $fhicl_patch_url"; exit 1; }
    git -C fhicl-cpp apply $Base/deps/fhicl-cpp-db.patch || { echo "ERROR: fhicl-cpp patch did not apply (fhicl-cpp develop moved?)"; exit 1; }
fi
# macOS: the default filesystem ignores case, so a source-root VERSION file is found by libc++'s own
# `#include <version>` whenever that root is on the include path (cetlib), and the build fails with
# "expected unqualified-id" on the version string. Rename it and tell cet_set_version_from_file. Idempotent.
if [ $is_mac -eq 1 ]; then
    for p in */; do
        p=${p%/}
        [ "$p" = cetmodules ] && continue   # CMake-only, no C++ include path
        if [ -f $p/VERSION ] && grep -q "cet_set_version_from_file(" $p/CMakeLists.txt 2>/dev/null \
           && ! grep -q "VERSION_FILE.*VERSION.txt" $p/CMakeLists.txt; then
            mv $p/VERSION $p/VERSION.txt
            sed -i '' 's|cet_set_version_from_file(|cet_set_version_from_file(VERSION_FILE ${PROJECT_SOURCE_DIR}/VERSION.txt |' $p/CMakeLists.txt
            echo "macOS: renamed $p/VERSION to VERSION.txt (case-insensitive clash with <version>)"
        fi
    done
fi
cd $Base
: > $Base/tmp/build-timings.txt
build_package Catch2 $Base/deps/Catch2 -DCMAKE_BUILD_TYPE=$build_type -DCMAKE_CXX_STANDARD=20 -DCMAKE_INSTALL_PREFIX=$prefix -DBUILD_TESTING=OFF || exit 1

########################################
## System libraries otsdaq needs: use the OS copy if present, otherwise build from source (no root needed).
## Boost, SQLite, TBB, OpenSSL, libcurl, Python are large and expected from the OS (see readme).
########################################
plain_flags="-DCMAKE_BUILD_TYPE=$build_type -DCMAKE_INSTALL_PREFIX=$prefix -DCMAKE_PREFIX_PATH=$prefix -DBUILD_TESTING=OFF"
# xerces-c (XML parser used by the otsdaq configuration layer)
if [ $build_xerces -eq 1 ]; then
    echo "xerces-c-devel not found on system; building xerces-c from source..."
    cd $Base/deps
    clone_dep xerces-c https://github.com/apache/xerces-c.git --depth 1 -b v3.3.0
    cd $Base
    build_package xerces-c $Base/deps/xerces-c $plain_flags -Dnetwork=OFF || exit 1
fi
# zeromq + cppzmq (FE -> Supervisor publish/subscribe in CoreSupervisors)
if [ $build_zmq -eq 1 ]; then
    echo "cppzmq-devel not found on system; building libzmq and cppzmq from source..."
    cd $Base/deps
    clone_dep libzmq https://github.com/zeromq/libzmq.git --depth 1 -b v4.3.5
    clone_dep cppzmq https://github.com/zeromq/cppzmq.git --depth 1 -b v4.10.0
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
    # any failure aborts: otherwise the build would silently use whatever branch is checked out
    if ! [ -d $pkg ]; then
        git clone $repo_base/$pkg          || { echo "ERROR: git clone $repo_base/$pkg failed"; exit 1; }
        git -C $pkg checkout $branch       || { echo "ERROR: branch '$branch' not found in $pkg"; exit 1; }
    elif [ $opt_no_pull -eq 0 ]; then
        git -C $pkg checkout $branch       || { echo "ERROR: branch '$branch' not found in $pkg"; exit 1; }
        git -C $pkg pull                   || { echo "ERROR: git pull failed in $pkg"; exit 1; }
    fi
}

cd $Base
test -L srcs && rm srcs
mkdir -p srcs
cd srcs
for pkg in otsdaq otsdaq-components otsdaq-utilities otsdaq-demo;do
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
# TRACE shell functions (tlvls, tshow, tonM, ...); the Spack trace package sourced this automatically, lite must do it here
[ -f \$SCRIPT_DIR/local/install/bin/trace_functions.sh ] && source \$SCRIPT_DIR/local/install/bin/trace_functions.sh

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
unalias mb mz 2>/dev/null   # earlier versions of this file defined mb/mz as aliases, which would shadow the functions
OTS_REPO_LIST_FILE=$Base/build/ots_repos.list
$(declare -f ots_discover_repos)
ots_cmake_configure()
{
    cmake -S $Base/srcs/\$1 -B $Base/build/\$1 $cet_cmake_flags_alias
}
# The repo list in \$OTS_REPO_LIST_FILE is established by the installer, i.e. by mz_uc;
# mb and mz only follow it (if there is no list yet, it is captured once from srcs/).
ots_repo_list_ready()
{
    if [ ! -s \$OTS_REPO_LIST_FILE ]; then
        echo "\$1: no repo list yet; capturing it from $Base/srcs (mz_uc re-establishes it)"
        mkdir -p $Base/build && ots_discover_repos $Base/srcs > \$OTS_REPO_LIST_FILE
    fi
    echo "\$1: repos: \$(tr '\n' ' ' < \$OTS_REPO_LIST_FILE)"
}
# mb: incremental build over the repo list. A repo in the list that has not been
# configured yet is configured first.
mb()
{
    local start_time=\$(date +%s) p
    date
    ots_repo_list_ready mb
    for p in \$(cat \$OTS_REPO_LIST_FILE); do
        { [ -f $Base/build/\$p/CMakeCache.txt ] || ots_cmake_configure \$p; } && cmake --build $Base/build/\$p -j\$BUILD_J && cmake --install $Base/build/\$p || break
    done
    date
    echo "Full time: \$((\$(date +%s) - start_time)) seconds"
}
# mz: clean build of every repo in the repo list
mz()
{
    local start_time=\$(date +%s) p
    date
    ots_repo_list_ready mz
    for p in \$(cat \$OTS_REPO_LIST_FILE); do
        rm -rf $Base/build/\$p; ots_cmake_configure \$p && cmake --build $Base/build/\$p -j\$BUILD_J && cmake --install $Base/build/\$p || break
    done
    date
    echo "Full time: \$((\$(date +%s) - start_time)) seconds"
}
# ultra clean: update the installer from srcs/otsdaq-demo (git pull, so it also works with a local --repo-base),
# then wipe build/ and local/install and rebuild everything. The copy is taken before anything is removed.
# The rerun installer re-establishes the repo list from srcs/ (build/ots_repos.list) that mb and mz follow.
alias  mz_uc='date; start_time=\$(date +%s); (cd $Base && { git -C srcs/otsdaq-demo pull --ff-only || echo "WARNING: could not pull srcs/otsdaq-demo; using its current copy of the installer"; } && cp srcs/otsdaq-demo/tools/ots-quick-lite-start.sh tmp/ots-quick-lite-start.sh && chmod 755 tmp/ots-quick-lite-start.sh && rm -rf $Base/build $Base/local/install $Base/tmp/build-timings.txt && ./tmp/ots-quick-lite-start.sh --no-pull $lite_rerun_opts); end_time=\$(date +%s); date; echo "Full time: \$((end_time - start_time)) seconds"'

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
echo -e "setup_ots.sh:\${LINENO} |  \t            mb                             ### for incremental build (of the repo list)"
echo -e "setup_ots.sh:\${LINENO} |  \t            mz                             ### for clean build (of the repo list)"
echo -e "setup_ots.sh:\${LINENO} |  \t            mz_uc                          ### for ultra clean build (also rebuilds dependencies and re-establishes the repo list from srcs/)"
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

# Install the tutorial Data and databases on first install only; rebuilds (mz_uc) leave them alone.
# The helper scripts are taken from the local checkout (no unauthenticated downloads).
# get_tutorial_data.sh backs up and replaces BOTH areas, so it is only run when both are absent.
if ! [ -d Data ] && ! [ -d databases ]; then
    cp $Base/srcs/otsdaq-demo/tools/get_tutorial_data.sh . && chmod 755 get_tutorial_data.sh \
      || { echo "ERROR: srcs/otsdaq-demo/tools/get_tutorial_data.sh not found"; exit 1; }
    export USER_DATA="$Base/Data"
    export ARTDAQ_DATABASE_URI="filesystemdb://$Base/databases/filesystemdb/test_db"
    ./get_tutorial_data.sh
    rm -rf $Base/tmp/script_log; mv $Base/script_log $Base/tmp/ 2>/dev/null
    rm -f get_tutorial_data.sh
    [ -d Data ] && [ -d databases ] || { echo "ERROR: get_tutorial_data.sh did not create Data/ and databases/ (see $Base/tmp/script_log)"; exit 1; }

    cp $Base/srcs/otsdaq-demo/tools/reset_ots_tutorial.sh . && chmod 755 reset_ots_tutorial.sh
elif ! [ -d Data ] || ! [ -d databases ]; then
    echo "ERROR: only one of Data/ and databases/ exists in $Base; refusing to guess."
    echo "       Either restore the missing one from a Data.bak*/databases.bak* copy, or move the other one"
    echo "       aside too and rerun to install a fresh tutorial set (both are backed up by get_tutorial_data.sh)."
    exit 1
else
    echo -e "ots-quick-lite-start.sh [${LINENO}]  \t Data/ and databases/ already present, keeping them"
fi

export USER_DATA="$Base/Data"
export ARTDAQ_DATABASE_URI="filesystemdb://$Base/databases/filesystemdb/test_db"


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
    mkdir -p $Base/build
    ots_discover_repos $Base/srcs > $Base/build/ots_repos.list    # the list mb follows
    for pkg in $(cat $Base/build/ots_repos.list); do
        build_package $pkg $Base/srcs/$pkg $cet_cmake_flags
        installStatus=$?
        if [ $installStatus -ne 0 ]; then
            echo "ERROR: build of $pkg failed (full log in $Base/tmp/)"
            break
        fi
    done
fi

echo
echo "=== build timings:"
cat $Base/tmp/build-timings.txt
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
