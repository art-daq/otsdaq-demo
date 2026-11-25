#ifndef _ots_DemoDQMHistoReceiverConsumer_h_
#define _ots_DemoDQMHistoReceiverConsumer_h_

#include "otsdaq-demo/ArtModules/HistoReceiver.hh"
#include "otsdaq/Configurable/Configurable.h"
#include "otsdaq/DataManager/DQMHistosConsumerBase.h"

#include <map>
#include <string>

namespace ots
{
/// DQM consumer for histograms that were filled somewhere else (for example in an
/// art module reading from an artdaq Dispatcher) and sent with HistoSender to the
/// buffer this consumer reads (for example through a TCPDataListenerProducer).
/// Every packet is unpacked into the DQM file of the run, which the Visualizer
/// shows live.
///
/// It uses the same table as DemoDQMHistosConsumer (DQMHistosConsumerTable:
/// SaveDQMFile, DQMFilePath, DQMFileNamePrefix).
class DemoDQMHistoReceiverConsumer : public DQMHistosConsumerBase, public Configurable
{
  public:
	DemoDQMHistoReceiverConsumer(std::string              supervisorApplicationUID,
	                             std::string              bufferUID,
	                             std::string              processorUID,
	                             const ConfigurationTree& theXDAQContextConfigTree,
	                             const std::string&       configurationPath);
	virtual ~DemoDQMHistoReceiverConsumer(void);

	void startProcessingData(std::string runNumber) override;
	void stopProcessingData(void) override;

  private:
	bool workLoopThread(toolbox::task::WorkLoop* workLoop) override;
	void fastRead(void);

	std::string*                        dataP_;
	std::map<std::string, std::string>* headerP_;

	bool        saveDQMFile_;
	std::string DQMFilePath_;
	std::string DQMFilePrefix_;

	HistoReceiver histoReceiver_;
};
}  // namespace ots

#endif
