#include "otsdaq-demo/ArtModules/HistoReceiver.hh"

#include "otsdaq/Macros/CoutMacros.h"

#include <TBufferFile.h>
#include <TDirectory.h>
#include <TGraph.h>
#include <TH1.h>
#include <TObject.h>
#include <TString.h>

#include <algorithm>

namespace ots
{
namespace
{
constexpr UInt_t histoPacketMagic = 0x4f545331;  // 'OTS1'
}

//==============================================================================
void HistoReceiver::addHistogram(TH1*        receivedHistogram,
                                 TDirectory* directory,
                                 MergeMode   mode)
{
	receivedHistogram->SetDirectory(nullptr);
	TH1* existingHistogram =
	    dynamic_cast<TH1*>(directory->FindObject(receivedHistogram->GetName()));
	if(existingHistogram == nullptr)
	{
		receivedHistogram->SetDirectory(directory);  // the directory owns it now
		return;
	}
	if(mode == MergeMode::Replace)
		existingHistogram->Reset();
	existingHistogram->Add(receivedHistogram);
	delete receivedHistogram;
}

//==============================================================================
void HistoReceiver::addGraph(TGraph* receivedGraph, TDirectory* directory)
{
	TGraph* existingGraph =
	    dynamic_cast<TGraph*>(directory->FindObject(receivedGraph->GetName()));
	if(existingGraph == nullptr)
	{
		directory->Append(receivedGraph);  // the directory owns it now
		return;
	}
	existingGraph->Set(0);
	for(int i = 0; i < receivedGraph->GetN(); ++i)
		existingGraph->SetPoint(i, receivedGraph->GetX()[i], receivedGraph->GetY()[i]);
	delete receivedGraph;
}

//==============================================================================
void HistoReceiver::addObject(TObject*    receivedObject,
                              TDirectory* directory,
                              MergeMode   mode)
{
	if(receivedObject->InheritsFrom(TH1::Class()))
	{
		addHistogram(static_cast<TH1*>(receivedObject), directory, mode);
		++lastObjectCount_;
		return;
	}
	if(receivedObject->InheritsFrom(TGraph::Class()))
	{
		addGraph(static_cast<TGraph*>(receivedObject), directory);
		++lastObjectCount_;
		return;
	}
	__COUT__ << "HistoReceiver skipped an object of a type it does not handle, named "
	         << receivedObject->GetName() << std::endl;
	delete receivedObject;
}

//==============================================================================
std::vector<std::string> HistoReceiver::readPacket(TDirectory*        topDirectory,
                                                   const std::string& packet)
{
	std::vector<std::string> topDirectoryNames;
	lastObjectCount_ = 0;

	TBufferFile message(TBuffer::kWrite);
	message.WriteBuf(packet.data(), packet.size());
	message.SetReadMode();
	message.SetBufferOffset(0);

	const int   packetLength = packet.size();
	std::string directoryName;
	while(message.Length() < packetLength)
	{
		message.ReadStdString(directoryName);
		if(directoryName.empty())
			break;

		MergeMode mode = MergeMode::Add;
		if(directoryName.find(":") != std::string::npos)
		{
			mode          = parseMergeMode(directoryName.substr(directoryName.find(":") + 1));
			directoryName = directoryName.substr(0, directoryName.find(":"));
		}

		std::string topDirectoryName = directoryName.substr(0, directoryName.find('/'));
		if(!topDirectoryName.empty() &&
		   std::find(topDirectoryNames.begin(),
		             topDirectoryNames.end(),
		             topDirectoryName) == topDirectoryNames.end())
			topDirectoryNames.push_back(topDirectoryName);

		TDirectory* directory = topDirectory;
		TString     directoryPath(directoryName);
		TString     directoryPathPiece;
		Ssiz_t      tokenizeFrom = 0;
		while(directoryPath.Tokenize(directoryPathPiece, tokenizeFrom, "/"))
			directory = directory->mkdir(directoryPathPiece.Data(), "", kTRUE);

		if(packetLength - message.Length() < static_cast<int>(2 * sizeof(UInt_t)))
		{
			__COUT__ << "HistoReceiver got a packet that ends after directory name '"
			         << directoryName << "'; the rest is dropped." << std::endl;
			break;
		}
		UInt_t magic       = 0;
		UInt_t objectCount = 0;
		message >> magic;
		if(magic != histoPacketMagic)
		{
			__COUT__ << "HistoReceiver got a packet without the expected marker after "
			            "directory name '"
			         << directoryName << "'; the rest is dropped." << std::endl;
			break;
		}
		message >> objectCount;

		bool blockIsComplete = true;
		for(UInt_t i = 0; i < objectCount; ++i)
		{
			TObject* receivedObject =
			    static_cast<TObject*>(message.ReadObjectAny(TObject::Class()));
			if(receivedObject == nullptr)
			{
				__COUT__ << "HistoReceiver could not read object " << i << " of "
				         << objectCount << " for directory '" << directoryName
				         << "'; the rest is dropped." << std::endl;
				blockIsComplete = false;
				break;
			}
			addObject(receivedObject, directory, mode);
		}
		if(!blockIsComplete)
			break;
	}
	topDirectory->cd();
	return topDirectoryNames;
}

//==============================================================================
HistoReceiver::MergeMode HistoReceiver::parseMergeMode(const std::string& modeName) const
{
	if(modeName == "replace")
		return MergeMode::Replace;
	return MergeMode::Add;
}
}  // namespace ots
