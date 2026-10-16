#ifndef OTSDAQ_DEMO_OTSDAQ_DEMO_FEINTERFACES_FEOTSETHERNETPROGRAMINTERFACE_H_
#define OTSDAQ_DEMO_OTSDAQ_DEMO_FEINTERFACES_FEOTSETHERNETPROGRAMINTERFACE_H_

#include "otsdaq-components/FEInterfaces/FEOtsUDPTemplateInterface.h"

//#include "otsdaq/FECore/FEVInterface.h"
//#include "otsdaq-components/DAQHardware/OtsUDPHardware.h"
//#include "otsdaq-components/DAQHardware/OtsUDPFirmwareDataGen.h"
//#include "otsdaq-demo/FEInterfaces/FEOtsUDPTemplateInterface.h"

#include <string>

namespace ots
{
class FEOtsEthernetProgramInterface
    : public FEOtsUDPTemplateInterface  ///< public FEVInterface, public OtsUDPHardware,
                                        ///< public OtsUDPFirmwareDataGen
{
  public:
	/// FEOtsEthernetProgramInterface     (unsigned int name=0, std::string
	/// daqHardwareType="daqHardwareType",	std::string firmwareType="firmwareType", const
	/// FEInterfaceTableBase* configuration=0);
	FEOtsEthernetProgramInterface(const std::string&       interfaceUID,
	                              const ConfigurationTree& theXDAQContextConfigTree,
	                              const std::string&       interfaceConfigurationPath);
	virtual ~FEOtsEthernetProgramInterface(void);

	void configure(void) override;
	// void halt             				(void) override;
	// void pause            				(void) override;
	// void resume           				(void) override;
	// void start            				(std::string runNumber) override;
	// void stop             				(void) override;
	// bool running   		  				(void) override;

	void getListOfProgramFiles(__ARGS__);
	void loadProgramFile(__ARGS__);

	///////////////////////
	/// inherits these from Template interface
	///
	///	virtual int universalRead	  	(char* address, char* readValue) override;
	///	virtual void universalWrite	  	(char* address, char* writeValue) override;
	/// private:
	///	void runSequenceOfCommands(const std::string &treeLinkName);
};
}  // namespace ots

#endif  // OTSDAQ_DEMO_OTSDAQ_DEMO_FEINTERFACES_FEOTSETHERNETPROGRAMINTERFACE_H_
