#ifndef OTSDAQ_DEMO_OTSDAQ_DEMO_SLOWCONTROLSINTERFACEPLUGINS_SLOWCONTROLSINTERFACETEMPLATE_H_
#define OTSDAQ_DEMO_OTSDAQ_DEMO_SLOWCONTROLSINTERFACEPLUGINS_SLOWCONTROLSINTERFACETEMPLATE_H_

#include <array>
#include <string>

#include "otsdaq/SlowControlsCore/SlowControlsVInterface.h"

namespace ots
{
// clang-format off
class SlowControlsInterfaceTemplate : public SlowControlsVInterface
{
  public:
	SlowControlsInterfaceTemplate(const std::string&       pluginType,
	                              const std::string&       interfaceUID,
	                              const ConfigurationTree& theXDAQContextConfigTree,
	                              const std::string&       controlsConfigurationPath);
	~SlowControlsInterfaceTemplate(void);

	void initialize() override;
	void destroy();

    std::vector<std::string /***Name  */> 			getChannelList		(void) override;
	std::string                					getList				(const std::string& format) override;
	void                       					subscribe			(const std::string& Name)  override;
	void                       					subscribeJSON		(const std::string& List) override;
	void                       					unsubscribe			(const std::string& Name) override;
	std::array<std::string, 4> 					getCurrentValue		(const std::string& Name) override;
	std::array<std::string, 9>					getSettings			(const std::string& Name) override;
	std::vector<std::vector<std::string>> 		getChannelHistory	(const std::string& Name, int startTime, int endTime) override;

	std::vector<std::vector<std::string>>		getLastAlarms		(const std::string& pvName) override;
	std::vector<std::vector<std::string>>		getAlarmsLog		(const std::string& pvName) override;
	std::vector<std::vector<std::string>>		checkAlarmNotifications	(void) override;

	virtual bool 								running				(void) override; ///<This is a workloop/thread, by default do nothing and end thread during running (Note: return true would repeat call)

};
// clang-format on
}  // namespace ots

#endif  // OTSDAQ_DEMO_OTSDAQ_DEMO_SLOWCONTROLSINTERFACEPLUGINS_SLOWCONTROLSINTERFACETEMPLATE_H_
