#ifndef _ots_demo_HistoSender_hh_
#define _ots_demo_HistoSender_hh_

#include <chrono>
#include <map>
#include <memory>
#include <string>
#include <vector>

class TH1;
class TGraph;
class TBufferFile;

namespace ots
{
class TCPSendClient;

/// Sends ROOT histograms and graphs over TCP to an otsdaq Data Manager buffer (for
/// example one filled by a TCPDataListenerProducer), where a DQM consumer such as
/// DemoDQMHistoReceiverConsumer unpacks them with HistoReceiver for the Visualizer.
///
/// Packet layout (one or more blocks):
///   directory name (std::string, optionally ending in ":replace" or ":add")
///   magic 0x4f545331 ('OTS1'), object count, then the objects
///
/// The connection is opened on the first send and reopened after a failure, so the
/// sending process (usually art) never blocks or exits when the receiver is not up.
class HistoSender
{
  public:
	HistoSender(const std::string& serverHost,
	            int                serverPort,
	            unsigned int       secondsBetweenConnectionAttempts = 5);
	~HistoSender(void);

	/// All return true when the packet was handed to the socket.
	bool sendHistogram(const std::string& directoryName, TH1* histogram);
	bool sendHistograms(const std::string& directoryName, std::vector<TH1*>& histograms);
	bool sendHistograms(std::map<std::string, std::vector<TH1*>>& histogramsByDirectory);
	bool sendGraphs(std::map<std::string, std::vector<TGraph*>>& graphsByDirectory);

	bool isConnected(void) const { return sendClient_ != nullptr; }

  private:
	bool connectIfNeeded(void);
	bool sendBuffer(TBufferFile& packetBuffer);

	std::string                           serverHost_;
	int                                   serverPort_;
	unsigned int                          secondsBetweenConnectionAttempts_;
	std::unique_ptr<TCPSendClient>        sendClient_;
	bool                                  connectionWasAttempted_;
	std::chrono::steady_clock::time_point lastConnectionAttemptTime_;
};
}  // namespace ots

#endif
