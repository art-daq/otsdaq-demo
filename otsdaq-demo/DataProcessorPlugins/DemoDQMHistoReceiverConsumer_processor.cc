#include "otsdaq-demo/DataProcessorPlugins/DemoDQMHistoReceiverConsumer.h"
#include "otsdaq/Macros/CoutMacros.h"
#include "otsdaq/Macros/ProcessorPluginMacros.h"
#include "otsdaq/MessageFacility/MessageFacility.h"

#include <TDirectory.h>
#include <TFile.h>

#include <chrono>
#include <mutex>
#include <thread>

using namespace ots;

//==============================================================================
DemoDQMHistoReceiverConsumer::DemoDQMHistoReceiverConsumer(
    std::string              supervisorApplicationUID,
    std::string              bufferUID,
    std::string              processorUID,
    const ConfigurationTree& theXDAQContextConfigTree,
    const std::string&       configurationPath)
    : WorkLoop(processorUID)
    , DQMHistosConsumerBase(
          supervisorApplicationUID, bufferUID, processorUID, LowConsumerPriority)
    , Configurable(theXDAQContextConfigTree, configurationPath)
    , dataP_(nullptr)
    , headerP_(nullptr)
    , saveDQMFile_(theXDAQContextConfigTree.getNode(configurationPath)
                       .getNode("SaveDQMFile")
                       .getValue<bool>())
    , DQMFilePath_(theXDAQContextConfigTree.getNode(configurationPath)
                       .getNode("DQMFilePath")
                       .getValue<std::string>())
    , DQMFilePrefix_(theXDAQContextConfigTree.getNode(configurationPath)
                         .getNode("DQMFileNamePrefix")
                         .getValue<std::string>())
{
}

//==============================================================================
DemoDQMHistoReceiverConsumer::~DemoDQMHistoReceiverConsumer(void)
{
	DQMHistosBase::closeFile();
}

//==============================================================================
void DemoDQMHistoReceiverConsumer::startProcessingData(std::string runNumber)
{
	// The file must always be opened because the live DQM uses the pointer to it
	DQMHistosBase::openFile(DQMFilePath_ + "/" + DQMFilePrefix_ + "_Run" + runNumber +
	                        ".root");
	DQMHistosBase::myDirectory_ = DQMHistosBase::theFile_;
	DQMHistosBase::myDirectory_->cd();

	DataConsumer::startProcessingData(runNumber);
}

//==============================================================================
void DemoDQMHistoReceiverConsumer::stopProcessingData(void)
{
	DataConsumer::stopProcessingData();
	if(saveDQMFile_)
		DQMHistosBase::save();
	DQMHistosBase::closeFile();
}

//==============================================================================
bool DemoDQMHistoReceiverConsumer::workLoopThread(toolbox::task::WorkLoop* /*workLoop*/)
{
	fastRead();
	return WorkLoop::continueWorkLoop_;
}

//==============================================================================
void DemoDQMHistoReceiverConsumer::fastRead(void)
{
	if(DataConsumer::read(dataP_, headerP_) < 0 || dataP_ == nullptr)
	{
		std::this_thread::sleep_for(std::chrono::milliseconds(10));
		return;
	}

	{
		// the Visualizer takes the same lock while it copies a histogram
		std::lock_guard<std::mutex> lock(fillHistoMutex_);
		histoReceiver_.readPacket(DQMHistosBase::myDirectory_, *dataP_);
	}

	DataConsumer::setReadSubBuffer<std::string, std::map<std::string, std::string>>();
}

DEFINE_OTS_PROCESSOR(DemoDQMHistoReceiverConsumer)
