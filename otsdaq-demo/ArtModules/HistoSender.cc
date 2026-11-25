#include "otsdaq-demo/ArtModules/HistoSender.hh"

#include "otsdaq/Macros/CoutMacros.h"
#include "otsdaq/NetworkUtilities/TCPSendClient.h"

#include <TBufferFile.h>
#include <TGraph.h>
#include <TH1.h>

#include <exception>

namespace ots
{
namespace
{
constexpr UInt_t histoPacketMagic = 0x4f545331;  // 'OTS1'
}

//==============================================================================
HistoSender::HistoSender(const std::string& serverHost,
                         int                serverPort,
                         unsigned int       secondsBetweenConnectionAttempts)
    : serverHost_(serverHost)
    , serverPort_(serverPort)
    , secondsBetweenConnectionAttempts_(secondsBetweenConnectionAttempts)
    , connectionWasAttempted_(false)
{
}

//==============================================================================
HistoSender::~HistoSender(void) {}

//==============================================================================
/// Returns true when a connection to the receiver exists. One connection attempt is
/// made at most every secondsBetweenConnectionAttempts_ seconds.
bool HistoSender::connectIfNeeded(void)
{
	if(sendClient_)
		return true;

	auto now = std::chrono::steady_clock::now();
	if(connectionWasAttempted_ &&
	   now - lastConnectionAttemptTime_ <
	       std::chrono::seconds(secondsBetweenConnectionAttempts_))
		return false;
	connectionWasAttempted_    = true;
	lastConnectionAttemptTime_ = now;

	try
	{
		std::unique_ptr<TCPSendClient> newSendClient(
		    new TCPSendClient(serverHost_, serverPort_));
		newSendClient->connect(1 /*retry*/);
		sendClient_ = std::move(newSendClient);
	}
	catch(const std::exception& connectError)
	{
		__COUT__ << "HistoSender could not connect to " << serverHost_ << ":"
		         << serverPort_ << " (will try again in "
		         << secondsBetweenConnectionAttempts_
		         << " seconds): " << connectError.what() << std::endl;
		return false;
	}
	return true;
}

//==============================================================================
bool HistoSender::sendBuffer(TBufferFile& packetBuffer)
{
	if(!connectIfNeeded())
		return false;

	try
	{
		sendClient_->sendPacket(packetBuffer.Buffer(), packetBuffer.Length());
	}
	catch(const std::exception& sendError)
	{
		__COUT__ << "HistoSender lost the connection to " << serverHost_ << ":"
		         << serverPort_ << ": " << sendError.what() << std::endl;
		try
		{
			sendClient_.reset();  // a new client is made at the next send
		}
		catch(...)
		{
		}
		return false;
	}
	return true;
}

//==============================================================================
bool HistoSender::sendHistogram(const std::string& directoryName, TH1* histogram)
{
	std::vector<TH1*> histograms(1, histogram);
	return sendHistograms(directoryName, histograms);
}

//==============================================================================
bool HistoSender::sendHistograms(const std::string& directoryName,
                                 std::vector<TH1*>& histograms)
{
	TBufferFile packetBuffer(TBufferFile::kWrite);
	packetBuffer.WriteStdString(&directoryName);
	packetBuffer << histoPacketMagic;
	packetBuffer << static_cast<UInt_t>(histograms.size());
	for(size_t i = 0; i < histograms.size(); ++i)
		packetBuffer.WriteObject(histograms[i]);
	return sendBuffer(packetBuffer);
}

//==============================================================================
bool HistoSender::sendHistograms(
    std::map<std::string, std::vector<TH1*>>& histogramsByDirectory)
{
	TBufferFile packetBuffer(TBufferFile::kWrite);
	for(auto& directoryAndHistograms : histogramsByDirectory)
	{
		packetBuffer.WriteStdString(&directoryAndHistograms.first);
		packetBuffer << histoPacketMagic;
		packetBuffer << static_cast<UInt_t>(directoryAndHistograms.second.size());
		for(size_t i = 0; i < directoryAndHistograms.second.size(); ++i)
			packetBuffer.WriteObject(directoryAndHistograms.second[i]);
	}
	return sendBuffer(packetBuffer);
}

//==============================================================================
bool HistoSender::sendGraphs(std::map<std::string, std::vector<TGraph*>>& graphsByDirectory)
{
	TBufferFile packetBuffer(TBufferFile::kWrite);
	for(auto& directoryAndGraphs : graphsByDirectory)
	{
		packetBuffer.WriteStdString(&directoryAndGraphs.first);
		packetBuffer << histoPacketMagic;
		packetBuffer << static_cast<UInt_t>(directoryAndGraphs.second.size());
		for(size_t i = 0; i < directoryAndGraphs.second.size(); ++i)
			packetBuffer.WriteObject(directoryAndGraphs.second[i]);
	}
	return sendBuffer(packetBuffer);
}
}  // namespace ots
