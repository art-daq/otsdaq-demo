#include "otsdaq-demo/SlowControlsInterfacePlugins/SlowControlsInterfaceTemplate.h"
#include "otsdaq/Macros/SlowControlsPluginMacros.h"

using namespace ots;

//==============================================================================
SlowControlsInterfaceTemplate::SlowControlsInterfaceTemplate(
    const std::string&       pluginType,
    const std::string&       interfaceUID,
    const ConfigurationTree& theXDAQContextConfigTree,
    const std::string&       controlsConfigurationPath)
    //  :Socket            (
    //  theXDAQContextConfigTree.getNode(interfaceConfigurationPath).getNode("HostIPAddress").getValue<std::string>()
    // ,theXDAQContextConfigTree.getNode(interfaceConfigurationPath).getNode("HostPort").getValue<unsigned
    // int>())
    // ,
    : SlowControlsVInterface(
          pluginType, interfaceUID, theXDAQContextConfigTree, controlsConfigurationPath)
{
}

//==============================================================================
SlowControlsInterfaceTemplate::~SlowControlsInterfaceTemplate() { destroy(); }

//==============================================================================
void SlowControlsInterfaceTemplate::initialize() {}

//==============================================================================
void SlowControlsInterfaceTemplate::destroy() {}

//==============================================================================
std::vector<std::string /*Name*/> SlowControlsInterfaceTemplate::getChannelList()
{
	return {"a", "b"};
}

//==============================================================================
std::string SlowControlsInterfaceTemplate::getList(const std::string& /*format*/)
{
	//__COUT__ << theXDAQContextConfigTree.getNode(controlsConfigurationPath).getValue <<
	// std::endl;
	return (std::string) "list";
}

//==============================================================================
void SlowControlsInterfaceTemplate::subscribe(const std::string& /*Name*/) {}

//==============================================================================
void SlowControlsInterfaceTemplate::subscribeJSON(const std::string& /*List*/) {}

//==============================================================================
void SlowControlsInterfaceTemplate::unsubscribe(const std::string& /*Name*/) {}

//==============================================================================
std::array<std::string, 4> SlowControlsInterfaceTemplate::getCurrentValue(
    const std::string& /*Name*/)
{
	return {"a", "b", "c", "d"};
}

//==============================================================================
std::array<std::string, 9> SlowControlsInterfaceTemplate::getSettings(
    const std::string& /*Name*/)
{
	return {"a", "b", "c", "d", "e", "f", "g", "h", "i"};
}

//==============================================================================
std::vector<std::vector<std::string>> SlowControlsInterfaceTemplate::getLastAlarms(
    const std::string& /*pvName*/)
{
	return {std::vector<std::string>({"a", "b", "c", "d", "e"}),
	        std::vector<std::string>({"b", "b", "c", "d", "e"})};
}  // end getLastAlarms()

//==============================================================================
std::vector<std::vector<std::string>> SlowControlsInterfaceTemplate::getAlarmsLog(
    const std::string& /*pvName*/)
{
	return {std::vector<std::string>({"a", "b", "c", "d", "e"}),
	        std::vector<std::string>({"b", "b", "c", "d", "e"})};
}  // end getAlarmsLog()

//==============================================================================
std::vector<std::vector<std::string>>
SlowControlsInterfaceTemplate::checkAlarmNotifications()
{
	return {std::vector<std::string>({"a", "b", "c", "d", "e"}),
	        std::vector<std::string>({"b", "b", "c", "d", "e"})};
}  // end checkAlarmNotifications()

//==============================================================================
std::vector<std::vector<std::string>> SlowControlsInterfaceTemplate::getChannelHistory(
    const std::string& /*Name*/, int /*startTime*/, int /*endTime*/)
{
	return {std::vector<std::string>({"a", "b", "c", "d", "e"}),
	        std::vector<std::string>({"b", "b", "c", "d", "e"}),
	        std::vector<std::string>({"c", "b", "c", "d", "e"}),
	        std::vector<std::string>({"d", "b", "c", "d", "e"}),
	        std::vector<std::string>({"e", "b", "c", "d", "e"}),
	        std::vector<std::string>({"f", "b", "c", "d", "e"}),
	        std::vector<std::string>({"g", "b", "c", "d", "e"}),
	        std::vector<std::string>({"h", "b", "c", "d", "e"}),
	        std::vector<std::string>({"i", "b", "c", "d", "e"}),
	        std::vector<std::string>({"j", "b", "c", "d", "e"})};
}

//==============================================================================
bool SlowControlsInterfaceTemplate::running(void)
{
	if(1 /*error??*/)
	{
		__SS__ << "Had an error!" << __E__;
		__SS_THROW__;
	}
	else
		return true;
}

DEFINE_OTS_SLOW_CONTROLS(SlowControlsInterfaceTemplate)
