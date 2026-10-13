#ifndef OTSDAQ_DEMO_OTSDAQ_DEMO_FEINTERFACES_FRONTENDINTERFACETEMPLATE_H_
#define OTSDAQ_DEMO_OTSDAQ_DEMO_FEINTERFACES_FRONTENDINTERFACETEMPLATE_H_

#include <map>
#include <string>
#include "otsdaq/DetectorWriter/FrontEndVirtualInterface.h"

namespace ots
{
class FrontEndHardwareTemplate;
class FrontEndFirmwareTemplate;

class FrontEndInterfaceTemplate : public FEVInterface
{
  public:
	FrontEndInterfaceTemplate(std::string name);

	virtual ~FrontEndInterfaceTemplate(void);

	void configure(void);
	void halt(void);
	void pause(void);
	void resume(void);
	void start(std::string runNumber);
	void stop(void);
	bool running(void);

	int  universalRead(char* address, char* readValue) override;
	void universalWrite(char* address, char* writeValue) override;

  protected:
	FrontEndHardwareTemplate* theFrontEndHardware_;
	FrontEndFirmwareTemplate* theFrontEndFirmware_;
};
}  // namespace ots

#endif  // OTSDAQ_DEMO_OTSDAQ_DEMO_FEINTERFACES_FRONTENDINTERFACETEMPLATE_H_
