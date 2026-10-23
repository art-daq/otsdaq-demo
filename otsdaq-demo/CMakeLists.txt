if(NOT DEFINED ENV{OTS_LITE})
	add_subdirectory(FEInterfaces) # needs otsdaq-components
endif()
if(NOT DEFINED ENV{OTS_LITE})
	add_subdirectory(DataProcessorPlugins) # DemoDQMHistosConsumer needs ROOT
	add_subdirectory(DemoRootUtilities) # needs ROOT
endif()
if(NOT DEFINED ENV{OTS_LITE})
	add_subdirectory(InterfaceTest) # needs otsdaq-components
	add_subdirectory(ArtModules) # needs art/artdaq
	add_subdirectory(Generators)
	add_subdirectory(Overlays) # needs artdaq-core
endif()
add_subdirectory(SlowControlsInterfacePlugins)
add_subdirectory(DetectorReader)
#add_subdirectory(TemplateDirectory)
