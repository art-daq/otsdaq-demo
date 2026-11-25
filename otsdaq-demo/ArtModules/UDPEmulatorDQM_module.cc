////////////////////////////////////////////////////////////////////////
/// Class:       UDPEmulatorDQM
/// Module Type: analyzer
/// File:        UDPEmulatorDQM_module.cc
/// Description: Fills histograms from the data of ots_udp_hw_emulator after it
///              went through artdaq (UDPReceiver generator, fragment type UDP),
///              and sends them with HistoSender to an otsdaq Data Manager buffer,
///              where DemoDQMHistoReceiverConsumer unpacks them for the Visualizer.
///
/// Each UDP packet streamed by the emulator is
///     byte 0: type (1 = first packet of a burst, 2 = any later packet)
///     byte 1: sequence number (counts up by one per packet and wraps at 256)
///     byte 2 and up: data; in the default counter mode this is one 8-byte counter
/// The UDPReceiver generator puts the packets one after the other in a fragment
/// without marking where each one ends, so this module needs the packet size
/// (packet_size_bytes, 10 for the counter mode).
///
/// Parameters:
///     raw_data_label            (default "daq")
///     frag_type                 (default "UDP")
///     packet_size_bytes         (default 10)
///     histogram_server_host     (default "127.0.0.1")
///     histogram_server_port     (required; ServerPort of the TCP listener producer)
///     histogram_directory       (default "UDPEmulator")
///     seconds_between_sends     (default 1.0)
////////////////////////////////////////////////////////////////////////

#include "art/Framework/Core/EDAnalyzer.h"
#include "art/Framework/Core/ModuleMacros.h"
#include "art/Framework/Principal/Event.h"
#include "art/Framework/Principal/Handle.h"
#include "art/Framework/Principal/Run.h"
#include "fhiclcpp/ParameterSet.h"

#include "artdaq-core/Data/Fragment.hh"
#include "artdaq-ots/Overlays/UDPFragment.hh"
#include "otsdaq-demo/ArtModules/HistoSender.hh"
#include "otsdaq/Macros/CoutMacros.h"

#include <TH1.h>
#include <TH1I.h>

#include <chrono>
#include <cstdint>
#include <cstring>
#include <memory>
#include <string>
#include <vector>

namespace ots
{
class UDPEmulatorDQM;
}

class ots::UDPEmulatorDQM : public art::EDAnalyzer
{
  public:
	explicit UDPEmulatorDQM(fhicl::ParameterSet const& parameterSet);
	virtual ~UDPEmulatorDQM();

	void beginRun(art::Run const& run) override;
	void analyze(art::Event const& event) override;
	void endRun(art::Run const& run) override;

  private:
	void fillFromFragment(const artdaq::Fragment& fragment);
	void sendHistograms(void);

	static constexpr unsigned int packetHeaderSizeBytes  = 2;
	static constexpr unsigned int counterSizeBytes       = 8;
	static constexpr uint8_t      firstBurstPacketType   = 1;
	static constexpr uint8_t      middleBurstPacketType  = 2;

	std::string  rawDataLabel_;
	std::string  fragmentType_;
	unsigned int packetSizeBytes_;
	std::string  histogramDirectory_;
	double       secondsBetweenSends_;

	HistoSender histoSender_;

	std::unique_ptr<TH1I> sequenceNumberHistogram_;
	std::unique_ptr<TH1I> sequenceNumberStepHistogram_;
	std::unique_ptr<TH1I> counterStepHistogram_;
	std::unique_ptr<TH1I> packetsPerFragmentHistogram_;
	std::unique_ptr<TH1I> fragmentSizeHistogram_;

	bool                                  previousPacketExists_;
	uint8_t                               previousSequenceNumber_;
	uint64_t                              previousCounter_;
	bool                                  histogramsHaveNewEntries_;
	std::chrono::steady_clock::time_point lastSendTime_;
};

//==============================================================================
ots::UDPEmulatorDQM::UDPEmulatorDQM(fhicl::ParameterSet const& parameterSet)
    : EDAnalyzer(parameterSet)
    , rawDataLabel_(parameterSet.get<std::string>("raw_data_label", "daq"))
    , fragmentType_(parameterSet.get<std::string>("frag_type", "UDP"))
    , packetSizeBytes_(parameterSet.get<unsigned int>("packet_size_bytes", 10))
    , histogramDirectory_(
          parameterSet.get<std::string>("histogram_directory", "UDPEmulator"))
    , secondsBetweenSends_(parameterSet.get<double>("seconds_between_sends", 1.0))
    , histoSender_(parameterSet.get<std::string>("histogram_server_host", "127.0.0.1"),
                   parameterSet.get<int>("histogram_server_port"))
    , previousPacketExists_(false)
    , previousSequenceNumber_(0)
    , previousCounter_(0)
    , histogramsHaveNewEntries_(false)
    , lastSendTime_(std::chrono::steady_clock::now())
{
	if(packetSizeBytes_ <= packetHeaderSizeBytes)
	{
		__SS__ << "packet_size_bytes is " << packetSizeBytes_ << " but must be more than "
		       << packetHeaderSizeBytes
		       << " (one type byte, one sequence number byte, then the data)." << __E__;
		__SS_THROW__;
	}

	sequenceNumberHistogram_.reset(new TH1I(
	    "SequenceNumber", "Sequence Number;Sequence Number;Packets", 256, 0, 256));
	sequenceNumberStepHistogram_.reset(
	    new TH1I("SequenceNumberStep",
	             "Sequence Number Step Between Packets (1 Means None "
	             "Lost);Step;Packets",
	             256,
	             0,
	             256));
	counterStepHistogram_.reset(
	    new TH1I("CounterStep",
	             "Data Counter Step Between Packets;Step (Last Bin Holds Larger "
	             "Steps);Packets",
	             1025,
	             0,
	             1025));
	packetsPerFragmentHistogram_.reset(
	    new TH1I("PacketsPerFragment",
	             "Packets Per Fragment;Packets (Last Bin Holds Larger "
	             "Counts);Fragments",
	             101,
	             0,
	             101));
	fragmentSizeHistogram_.reset(
	    new TH1I("FragmentSize",
	             "Fragment Data Size;Bytes (Last Bin Holds Larger Sizes);Fragments",
	             151,
	             0,
	             1510));

	// keep the histograms out of any ROOT file that art has open
	for(TH1* histogram : std::vector<TH1*>{sequenceNumberHistogram_.get(),
	                                       sequenceNumberStepHistogram_.get(),
	                                       counterStepHistogram_.get(),
	                                       packetsPerFragmentHistogram_.get(),
	                                       fragmentSizeHistogram_.get()})
		histogram->SetDirectory(nullptr);
}

//==============================================================================
ots::UDPEmulatorDQM::~UDPEmulatorDQM() {}

//==============================================================================
void ots::UDPEmulatorDQM::beginRun(art::Run const& /*run*/)
{
	// steps are only filled between packets of the same run
	previousPacketExists_ = false;
}

//==============================================================================
void ots::UDPEmulatorDQM::analyze(art::Event const& event)
{
	art::Handle<artdaq::Fragments> fragmentsHandle;
	event.getByLabel(rawDataLabel_, fragmentType_, fragmentsHandle);

	if(fragmentsHandle.isValid())
		for(const auto& fragment : *fragmentsHandle)
			fillFromFragment(fragment);

	if(std::chrono::duration<double>(std::chrono::steady_clock::now() - lastSendTime_)
	       .count() >= secondsBetweenSends_)
		sendHistograms();
}

//==============================================================================
void ots::UDPEmulatorDQM::endRun(art::Run const& /*run*/) { sendHistograms(); }

//==============================================================================
void ots::UDPEmulatorDQM::fillFromFragment(const artdaq::Fragment& fragment)
{
	ots::UDPFragment udpFragment(fragment);

	const uint8_t* fragmentData      = udpFragment.dataBegin();
	const size_t   fragmentSizeBytes = udpFragment.udp_data_words();

	unsigned int packetCount = 0;
	for(size_t packetOffset = 0; packetOffset + packetSizeBytes_ <= fragmentSizeBytes;
	    packetOffset += packetSizeBytes_)
	{
		const uint8_t* packet     = fragmentData + packetOffset;
		const uint8_t  packetType = packet[0];
		// the bytes after the last packet are padding (zeros)
		if(packetType != firstBurstPacketType && packetType != middleBurstPacketType)
			break;
		++packetCount;

		const uint8_t sequenceNumber = packet[1];
		uint64_t      counter        = 0;
		const bool    packetHasCounter =
		    packetSizeBytes_ >= packetHeaderSizeBytes + counterSizeBytes;
		if(packetHasCounter)
			memcpy(&counter, packet + packetHeaderSizeBytes, counterSizeBytes);

		sequenceNumberHistogram_->Fill(sequenceNumber);
		if(previousPacketExists_ && packetType == middleBurstPacketType)
		{
			sequenceNumberStepHistogram_->Fill(
			    static_cast<uint8_t>(sequenceNumber - previousSequenceNumber_));
			if(packetHasCounter)
			{
				const uint64_t counterStep = counter - previousCounter_;
				counterStepHistogram_->Fill(counterStep > 1024 ? 1024 : counterStep);
			}
		}
		previousPacketExists_   = true;
		previousSequenceNumber_ = sequenceNumber;
		previousCounter_        = counter;
	}

	packetsPerFragmentHistogram_->Fill(packetCount > 100 ? 100 : packetCount);
	fragmentSizeHistogram_->Fill(fragmentSizeBytes > 1500 ? 1500 : fragmentSizeBytes);
	histogramsHaveNewEntries_ = true;
}

//==============================================================================
/// Sends what was filled since the last successful send, then empties the
/// histograms; the receiver adds each packet to what it already has. When the send
/// fails (receiver not up) the entries are kept for the next try.
void ots::UDPEmulatorDQM::sendHistograms(void)
{
	lastSendTime_ = std::chrono::steady_clock::now();
	if(!histogramsHaveNewEntries_)
		return;

	std::vector<TH1*> histograms{sequenceNumberHistogram_.get(),
	                             sequenceNumberStepHistogram_.get(),
	                             counterStepHistogram_.get(),
	                             packetsPerFragmentHistogram_.get(),
	                             fragmentSizeHistogram_.get()};

	if(!histoSender_.sendHistograms(histogramDirectory_ + ":add", histograms))
		return;

	for(TH1* histogram : histograms)
		histogram->Reset();
	histogramsHaveNewEntries_ = false;
}

DEFINE_ART_MODULE(ots::UDPEmulatorDQM)
