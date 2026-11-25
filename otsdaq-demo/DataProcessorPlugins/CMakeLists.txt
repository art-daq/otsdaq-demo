
include(otsdaq::dataProcessor)

cet_build_plugin(DemoDQMHistosConsumer otsdaq::dataProcessor LIBRARIES REG otsdaq-demo::DemoRootUtilities otsdaq::RootUtilities
)

# unpacks histograms sent with HistoSender (ArtModules); needs art/artdaq to be built
if(NOT DEFINED ENV{OTS_LITE})
	cet_build_plugin(DemoDQMHistoReceiverConsumer otsdaq::dataProcessor LIBRARIES REG otsdaq-demo::ArtModules otsdaq::RootUtilities ROOT::Core ROOT::RIO
	)
endif()

install_headers()
install_source()
