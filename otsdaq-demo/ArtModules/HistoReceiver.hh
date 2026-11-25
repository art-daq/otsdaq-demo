#ifndef _ots_demo_HistoReceiver_hh_
#define _ots_demo_HistoReceiver_hh_

#include <string>
#include <vector>

class TDirectory;
class TGraph;
class TH1;
class TObject;

namespace ots
{
/// Unpacks the packets made by HistoSender into a ROOT directory (see HistoSender.hh
/// for the packet layout).
class HistoReceiver
{
  public:
	enum class MergeMode
	{
		Add,     ///< add the received histogram to the one already there (default)
		Replace  ///< the received histogram takes the place of the one already there
	};

	/// Unpacks one packet into topDirectory. Returns the top-level directory name of
	/// every block in the packet.
	std::vector<std::string> readPacket(TDirectory*        topDirectory,
	                                    const std::string& packet);

	/// Histograms and graphs placed into the directory by the most recent readPacket.
	unsigned int lastObjectCount(void) const { return lastObjectCount_; }

  private:
	void      addObject(TObject* receivedObject, TDirectory* directory, MergeMode mode);
	void      addHistogram(TH1* receivedHistogram, TDirectory* directory, MergeMode mode);
	void      addGraph(TGraph* receivedGraph, TDirectory* directory);
	MergeMode parseMergeMode(const std::string& modeName) const;

	unsigned int lastObjectCount_ = 0;
};
}  // namespace ots

#endif
