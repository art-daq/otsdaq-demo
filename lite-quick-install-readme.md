# otsdaq lite — quick install on an empty Linux box

`ots-quick-lite-start.sh` installs and builds a lightweight otsdaq (no Spack, no CVMFS,
no xdaq, no artdaq) from source, using plain `cmake` + `gcc`. Only three repos are
used: `otsdaq`, `otsdaq-utilities`, `otsdaq-demo`. Target: minutes, not hours, on a
small machine such as an SoC running a stock Linux distribution.

Everything the script can build itself, it does (into `local/install`). The short list
below is what it *cannot* build and must come from your distribution's package manager.

## 1. System prerequisites (one-time, needs root)

The script needs these from the OS. Package names are for AlmaLinux / Rocky / RHEL 9;
equivalents exist on Debian/Ubuntu (`apt`) — use `g++-13` or newer there.

```bash
# toolchain: gcc >= 12 is required (cetlib uses constexpr std::string); AL9 ships gcc 11,
# so install the gcc-toolset-13 RPM. The script enables it automatically if present.
sudo dnf install gcc-toolset-13-gcc-c++ make git curl tar

# -devel libraries that otsdaq and the cet suite link against
sudo dnf install boost-devel sqlite-devel tbb-devel openssl-devel libcurl-devel python3-devel
```

Not needed from the OS — the script downloads or builds them into `local/install`
without root: `cmake` (user-space binary from Kitware), cetmodules, cetlib-except,
hep-concurrency, cetlib, fhicl-cpp, messagefacility, Catch2, TRACE, artdaq-database
(built with `WITH_MONGODB=OFF`, so no MongoDB driver or server), and — only if the OS
copy is missing — xerces-c, libzmq, cppzmq. (`sudo dnf install xerces-c-devel
cppzmq-devel` is still the faster route when you have root.)

The script cannot install RPMs itself (that needs root). If a required OS library is
missing and has no source fallback, `cmake` stops with a `Failed to find <Name>` error
naming it; install the matching `-devel` package and rerun.

Internet access to `github.com` is required during install.

## 2. Install (three steps, no root)

```bash
mkdir ots && cd ots
wget https://raw.githubusercontent.com/art-daq/otsdaq-demo/develop/tools/ots-quick-lite-start.sh
chmod +x ots-quick-lite-start.sh
./ots-quick-lite-start.sh
```

That is it. The script:

1. enables `gcc-toolset-13` if found, downloads `cmake` into `./cmake` if the system one is too old (< 3.24)
2. clones and builds the cet suite, TRACE, and artdaq-database into `./local/install`
   (~90 s on 24 cores). fhicl-cpp gets the small `raw_value` patch that artdaq-database
   needs (the same one the `fhicl-cpp+db` Spack variant applies).
3. clones the three otsdaq repos into `./srcs` (read-only HTTPS, no credentials)
4. builds otsdaq, otsdaq-utilities, otsdaq-demo into `./local/install`
5. writes `setup_ots.sh` and prints per-package build timings

A full log of every run is kept in `qls-log/`.

Options: `--debug` (Debug build), `--branch <name>` (git branch for the three repos,
default `develop`), `--repo-base <url-or-dir>` (where to clone from; a local directory
works for development), `--no-build` (stop after sources are checked out).

## 3. Using it afterwards

In every new terminal:

```bash
cd ots
source setup_ots.sh
```

This exports `OTS_LITE=1`, enables the toolchain, puts `local/install` on `PATH` /
`LD_LIBRARY_PATH`, and defines the compile aliases:

| alias   | what it does |
|---------|--------------|
| `mb`    | incremental build of the three otsdaq repos (`cmake --build` + install) |
| `mz`    | clean build: wipe `build/`, re-run cmake, build, install |
| `mz_uc` | ultra-clean: wipe `build/` **and** `local/install`, rebuild deps and otsdaq from scratch (re-evaluates all dependencies — the cmake equivalent of `spack concretize`) |

Then `ots --wiz` to configure, `ots` to start, `kx` to kill (see `ots --help`).

## 4. What "lite" means

`OTS_LITE=1` is the single switch. It is exported by the install script and by
`setup_ots.sh`, and the CMakeLists files check `if(DEFINED ENV{OTS_LITE})` to:

- skip `find_package` for artdaq, artdaq-core, XDAQ, otsdaq-components
- not build the `artdaq-ots` tree, the `ARTDAQ*` modules/plugins, and the otsdaq-demo
  pieces that need art/artdaq or otsdaq-components
- replace the artdaq link targets in the core libraries with `otsdaq::XdaqLite`, a thin
  header-compatible stand-in for the xdaq/artdaq classes the Supervisors use
- keep the real artdaq-database `Database` configuration plugin (full read/write of the
  `filesystemdb` configuration database); only the MongoDB provider is left out

The same CMakeLists build the full system when `OTS_LITE` is unset. There is no separate
lite branch of the source tree — one tree, one env var.

## 5. Layout after install

```
ots/
  ots-quick-lite-start.sh   the installer
  setup_ots.sh              source this in each new terminal
  cmake/                    user-space cmake (only if the system one was too old)
  deps/                     cet suite sources
  srcs/                     otsdaq, otsdaq-utilities, otsdaq-demo
  build/                    cmake build trees
  local/install/            everything installed (deps + otsdaq)
  qls-log/                  install logs
  Data/ databases/          runtime data and configuration database
```

## 6. Known limits / work in progress

- xdaq is still referenced by ~100 source files (Supervisors, SOAP, FSM, WorkLoop).
  Removing the artdaq dependence is done at the CMake level; removing xdaq is a
  source-level job and is the next phase. Until then the build stops where xdaq
  headers are first needed — the script shows you exactly where.
- `Data/` and `databases/` seed content still comes from the `otsdaq_demo` repo
  (`NoGitData`, `NoGitDatabases`) and the tutorial data scripts, as in the full install.
- Tested on AlmaLinux 9.6 x86_64 with gcc-toolset-13. Other distributions and
  aarch64 SoCs should work with the equivalent packages but have not been tried yet.
