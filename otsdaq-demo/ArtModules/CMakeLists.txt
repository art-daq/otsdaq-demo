include(BuildPlugins)

# HistoSender (used by art modules) and HistoReceiver (used by DQM consumers)
cet_make_library(
SOURCE HistoReceiver.cc HistoSender.cc
LIBRARIES PUBLIC
otsdaq::NetworkUtilities
otsdaq::Macros
ROOT::Core
ROOT::RIO
ROOT::Hist
)

cet_build_plugin(ODWFViewer art::module LIBRARIES PRIVATE otsdaq-demo::Overlays ROOT::Core ROOT::Gui otsdaq::MessageFacility)

cet_build_plugin(UDPEmulatorDQM art::module LIBRARIES PRIVATE
otsdaq-demo::ArtModules
otsdaq-artdaqinterface::artdaq-ots_Overlays
artdaq-core::Data
otsdaq::Macros
ROOT::Core
ROOT::Hist
)

install_headers()
install_source()
