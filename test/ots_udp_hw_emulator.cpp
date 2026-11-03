/// ots_udp_hw_emulator.cpp
///    by rrivera at fnal dot gov
///	  created Feb 2016
///
/// This is a simple emulator of a "data gen" front-end (hardware) interface
/// using the otsdaq UDP protocol.
///
/// compile with:
/// g++ ots_udp_hw_emulator.cpp -o hw.o
///
/// if developing, consider appending -D_GLIBCXX_DEBUG to get more
/// descriptive error messages
///
/// run with:
///./hw.o
///
///
#include <arpa/inet.h>
#include <errno.h>
#include <netdb.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>
#include <cmath>
#include <iomanip>
#include <iostream>
#include <sstream>

/// take only file name
#define __FILENAME__ (strrchr(__FILE__, '/') ? strrchr(__FILE__, '/') + 1 : __FILE__)

/// use this for normal printouts
#define __PRINTF__ printf
#define __COUT__ std::cout << __FILENAME__ << std::dec << ":" << __LINE__ << "\t"

/// and use this to suppress
///#define __PRINTF__ if(0) printf
///#define __COUT__  if(0) cout
///
#define MAXBUFLEN 1492
#define EMULATOR_PORT "4950"  // Can be also passed as first argument

/// get sockaddr, IPv4 or IPv6:
void* get_in_addr(struct sockaddr* sa)
{
	if(sa->sa_family == AF_INET)
	{
		return &(((struct sockaddr_in*)sa)->sin_addr);
	}

	return &(((struct sockaddr_in6*)sa)->sin6_addr);
}

unsigned int bytesPerSample(uint16_t bitWidth)
{
	if(bitWidth <= 8)
		return 1;
	if(bitWidth <= 16)
		return 2;
	return 4;
}

uint32_t generateWaveformSample(int channel, time_t count, uint32_t maxVal)
{
	double t  = (double)count;
	double v  = 0;
	int    ch = channel % 8;
	switch(ch)
	{
	case 0:  // sine, period 100
		v = 0.5 + 0.5 * sin(2.0 * M_PI * t / 100.0);
		break;
	case 1:  // sine, period 50
		v = 0.5 + 0.5 * sin(2.0 * M_PI * t / 50.0);
		break;
	case 2:  // triangle, period 100
	{
		double phase = fmod(t, 100.0) / 100.0;
		v            = (phase < 0.5) ? (phase * 2.0) : (2.0 - phase * 2.0);
		break;
	}
	case 3:  // triangle, period 60
	{
		double phase = fmod(t, 60.0) / 60.0;
		v            = (phase < 0.5) ? (phase * 2.0) : (2.0 - phase * 2.0);
		break;
	}
	case 4:  // step / square wave, period 80
		v = (fmod(t, 80.0) < 40.0) ? 1.0 : 0.0;
		break;
	case 5:  // step, period 40
		v = (fmod(t, 40.0) < 20.0) ? 1.0 : 0.0;
		break;
	case 6:  // sine + varying offset, period 100
		v = 0.5 + 0.4 * sin(2.0 * M_PI * t / 100.0) + 0.1 * sin(2.0 * M_PI * t / 7.0);
		break;
	case 7:  // sawtooth, period 100
		v = fmod(t, 100.0) / 100.0;
		break;
	}
	if(v < 0.0)
		v = 0.0;
	if(v > 1.0)
		v = 1.0;
	return (uint32_t)(v * maxVal);
}

unsigned int fillBurstPayload(char*    buff,
                              int      txOffset,
                              uint8_t  data_mode,
                              uint16_t sample_bit_width,
                              uint16_t samples_per_packet,
                              uint16_t num_channels,
                              uint16_t wave_period,
                              uint16_t wave_amplitude_pct,
                              uint16_t wave_offset_pct,
                              time_t   count)
{
	if(data_mode == 0)
	{
		memcpy((void*)&buff[txOffset], (void*)&count, 8);
		return txOffset + 8;
	}

	uint32_t     maxVal = (1u << sample_bit_width) - 1;
	unsigned int bps    = bytesPerSample(sample_bit_width);
	uint16_t     nch    = (data_mode == 1 || data_mode == 3) ? 1 : num_channels;
	uint16_t     nsamp  = samples_per_packet;
	double       period = wave_period ? (double)wave_period : 100.0;
	double       amp    = wave_amplitude_pct / 100.0;
	double       off    = wave_offset_pct / 100.0;

	if(nsamp == 0)
	{
		unsigned int maxPayload = MAXBUFLEN - txOffset;
		nsamp                   = maxPayload / (nch * bps);
		if(nsamp == 0)
			nsamp = 1;
	}

	unsigned int offset = txOffset;
	for(uint16_t s = 0; s < nsamp; ++s)
	{
		for(uint16_t ch = 0; ch < nch; ++ch)
		{
			// unit waveform v in [0,1], then scale/shift: offset + amplitude*(v-0.5)
			double v;
			if(data_mode == 1)  // sine
				v = 0.5 + 0.5 * sin(2.0 * M_PI * (count + s) / period);
			else if(data_mode == 3)  // sawtooth ramp
				v = fmod((double)(count + s), period) / period;
			else
				v = (double)generateWaveformSample(ch, count + s, maxVal) / maxVal;
			v = off + amp * (v - 0.5);
			if(v < 0.0)
				v = 0.0;
			if(v > 1.0)
				v = 1.0;
			uint32_t val = (uint32_t)(v * maxVal);

			if(offset + bps > MAXBUFLEN)
				return offset;

			if(bps == 1)
				buff[offset] = (char)(val & 0xFF);
			else if(bps == 2)
			{
				buff[offset]     = (char)(val & 0xFF);
				buff[offset + 1] = (char)((val >> 8) & 0xFF);
			}
			else
			{
				memcpy((void*)&buff[offset], (void*)&val, 4);
			}
			offset += bps;
		}
	}
	return offset;
}

int makeSocket(const char* ip, int port, struct addrinfo*& p)
{
	int             sockfd;
	struct addrinfo hints, *servinfo;
	int             rv;
	// int                     numberOfBytes;
	// struct sockaddr_storage their_addr;
	// socklen_t               addr_len;
	// char                    s[INET6_ADDRSTRLEN];

	memset(&hints, 0, sizeof hints);
	hints.ai_family   = AF_UNSPEC;
	hints.ai_socktype = SOCK_DGRAM;
	char portStr[10];
	sprintf(portStr, "%d", port);
	if((rv = getaddrinfo(ip, portStr, &hints, &servinfo)) != 0)
	{
		__PRINTF__("getaddrinfo: %s\n", gai_strerror(rv));
		return -1;
	}

	// loop through all the results and make a socket
	for(p = servinfo; p != NULL; p = p->ai_next)
	{
		if((sockfd = socket(p->ai_family, p->ai_socktype, p->ai_protocol)) == -1)
		{
			__PRINTF__("sw: socket\n");
			continue;
		}

		break;
	}

	if(p == NULL)
	{
		__PRINTF__("sw: failed to create socket\n");
		return -1;
	}

	freeaddrinfo(servinfo);

	return sockfd;
}

int main(int argc, char** argv)
{
	std::string emulatorPort(EMULATOR_PORT);
	if(argc == 2)
		emulatorPort = argv[1];

	__COUT__ << std::hex << ":::"
	         << "\n\nUsing emulatorPort=" << emulatorPort << "\n"
	         << std::endl;

	std::string streamToIP;
	uint32_t    streamToPort = 0;

	int                     sockfd;
	int                     sendSockfd = 0;
	struct addrinfo         hints, *servinfo, *p;
	int                     rv;
	int                     numberOfBytes;
	struct sockaddr_storage their_addr;
	char                    buff[MAXBUFLEN];
	socklen_t               addr_len;
	char                    s[INET6_ADDRSTRLEN];

	memset(&hints, 0, sizeof hints);
	hints.ai_family   = AF_UNSPEC;  // set to AF_INET to force IPv4
	hints.ai_socktype = SOCK_DGRAM;
	hints.ai_flags    = AI_PASSIVE;  // use my IP

	if((rv = getaddrinfo(NULL, emulatorPort.c_str(), &hints, &servinfo)) != 0)
	{
		fprintf(stderr, "getaddrinfo: %s\n", gai_strerror(rv));
		return 1;
	}

	// loop through all the results and bind to the first we can
	for(p = servinfo; p != NULL; p = p->ai_next)
	{
		if((sockfd = socket(p->ai_family, p->ai_socktype, p->ai_protocol)) == -1)
		{
			perror("listener: socket");
			continue;
		}

		if(bind(sockfd, p->ai_addr, p->ai_addrlen) == -1)
		{
			close(sockfd);
			perror("listener: bind");
			continue;
		}

		break;
	}

	if(p == NULL)
	{
		fprintf(stderr, "listener: failed to bind socket\n");

		__COUT__ << "\n\nYou can try a different port by passing an argument.\n\n";

		return 2;
	}

	freeaddrinfo(servinfo);

	//////////////////////////////////////////////////////////////////////
	////////////// ready to go //////////////
	//////////////////////////////////////////////////////////////////////

	// print address space
	std::stringstream addressSpaceSS;
	addressSpaceSS << "Address space:\n";
	addressSpaceSS << "\t 0x0000000000001001 \t W/R \t 'Data count'\n";
	addressSpaceSS << "\t 0x0000000000001002 \t W/R \t 'Data rate'\n";
	addressSpaceSS << "\t 0x0000000000001003 \t W/R \t 'LEDs'\n";
	addressSpaceSS << "\t 0x0000000100000006 \t W \t 'Stream destination IP'\n";
	// addressSpaceSS << "\t 0x0000000100000007 \t W \t 'Destination MAC address
	// ignored'\n";
	addressSpaceSS << "\t 0x0000000100000008 \t W \t 'Stream destination port'\n";
	addressSpaceSS << "\t 0x0000000100000009 \t W/R \t 'Burst data enable'\n";
	addressSpaceSS << "\t 0x0000000000001004 \t W/R \t 'Data mode (0=counter,1=sine "
	                  "1ch,2=multi-ch waveforms,3=sawtooth 1ch)'\n";
	addressSpaceSS << "\t 0x0000000000001005 \t W/R \t 'Sample bit width (8,12,16,32)'\n";
	addressSpaceSS
	    << "\t 0x0000000000001006 \t W/R \t 'Samples per packet (0=max fit)'\n";
	addressSpaceSS << "\t 0x0000000000001007 \t W/R \t 'Number of channels'\n";
	addressSpaceSS << "\t 0x0000000000001008 \t W/R \t 'Waveform period (samples/cycle, "
	                  "modes 1,3)'\n";
	addressSpaceSS << "\t 0x0000000000001009 \t W/R \t 'Waveform amplitude (% full "
	                  "scale, modes 1-3)'\n";
	addressSpaceSS << "\t 0x000000000000100A \t W/R \t 'Waveform offset (% full scale, "
	                  "modes 1-3)'\n";

	__COUT__ << addressSpaceSS.str() << "\n\n";

	// hardware "registers"
	uint64_t data_gen_cnt     = 0;
	uint64_t data_gen_rate    = 100;  // number of loops to wait
	uint8_t  led_register     = 0;
	uint8_t  dataEnabled      = 0;
	uint32_t streamToIP_reg   = 0;
	uint8_t  data_mode        = 0;  // 0=counter, 1=sine, 2=multi-ch waveforms, 3=sawtooth
	uint16_t sample_bit_width = 16;   // ADC resolution: 8, 12, 16, or 32
	uint16_t samples_per_packet = 1;  // 0 = auto-fill to max packet size
	uint16_t num_channels       = 1;
	uint16_t wave_period        = 100;  // samples per cycle (modes 1 and 3), 0 = 100
	uint16_t wave_amplitude_pct = 100;  // peak-to-peak as % of full scale (modes 1-3)
	uint16_t wave_offset_pct    = 50;   // waveform center as % of full scale (modes 1-3)

	const unsigned int RX_ADDR_OFFSET = 2;
	const unsigned int RX_DATA_OFFSET = 10;
	const unsigned int TX_DATA_OFFSET = 2;

	bool          wasDataEnabled = false;
	bool          wasDataSent    = false;
	unsigned char sequence       = 0;
	unsigned int  packetSz;

	// for timeout/select
	struct timeval tv;
	fd_set         readfds, masterfds;
	tv.tv_sec  = 0;
	tv.tv_usec = 0;  // 500000; RAR moved timeout to sleep to free up processor
	FD_ZERO(&masterfds);
	FD_SET(sockfd, &masterfds);

	time_t count = 0;

	int handlerIndex;
	int totalNumberOfBytes;

	while(1)
	{
		usleep(3000);  // sleep 3ms to free up processor (downfall is less responsive, but
		               // likely not noticeable)

		readfds = masterfds;  // copy to reset timeout select
		select(sockfd + 1, &readfds, NULL, NULL, &tv);

		if(FD_ISSET(sockfd, &readfds))
		{
			// packet received
			__COUT__ << std::hex << ":::"
			         << "Packet Received!" << std::endl;

			addr_len = sizeof their_addr;
			if((totalNumberOfBytes = recvfrom(sockfd,
			                                  buff,
			                                  MAXBUFLEN - 1,
			                                  0,
			                                  (struct sockaddr*)&their_addr,
			                                  &addr_len)) == -1)
			{
				perror("recvfrom");
				exit(1);
			}

			__COUT__ << ":::"
			         << "hw: got packet from "
			         << inet_ntop(their_addr.ss_family,
			                      get_in_addr((struct sockaddr*)&their_addr),
			                      s,
			                      sizeof s)
			         << std::endl;
			__COUT__ << ":::"
			         << "hw: packet total is " << totalNumberOfBytes << " bytes long"
			         << std::endl;
			//			__COUT__ << ":::" << "hw: packet contents \n";
			//			for(int i=0; i<totalNumberOfBytes; i++)
			//			{
			//				if(i%8==0) __COUT__ << "\t" << i << " " << std::endl;
			//				__PRINTF__("%2.2X", (unsigned char)buff[handlerIndex + i]);
			//				//__COUT__ << std::hex << std::setw(2) << (int)(unsigned
			// char)buff[i] << std::dec;
			//			}

			// treat as stacked packets
			handlerIndex = 0;

			while(handlerIndex < totalNumberOfBytes &&
			      (numberOfBytes = (buff[handlerIndex + 0]
			                            ? 18
			                            : 10)) &&  // assume write is 18 and read is 10
			      handlerIndex + numberOfBytes <= totalNumberOfBytes)
			{
				__COUT__ << ":::"
				         << "hw: packet byte index " << handlerIndex << std::endl;
				__COUT__ << ":::"
				         << "hw: packet is " << numberOfBytes << " bytes long"
				         << std::endl;

				for(int i = 0; i < numberOfBytes; i++)
				{
					if((i - RX_ADDR_OFFSET) % 8 == 0)
						__PRINTF__("\n");
					__PRINTF__("%2.2X", (unsigned char)buff[handlerIndex + i]);
					//__COUT__ << std::hex << std::setw(2) << (int)(unsigned char)buff[i]
					//<< std::dec;
				}
				__PRINTF__("\n");

				// handle packet
				if(numberOfBytes == 10 &&  // size is valid (type, size, 8-byte address)
				   buff[handlerIndex + 0] == 0)  // read
				{
					uint64_t addr;
					memcpy((void*)&addr, (void*)&buff[handlerIndex + RX_ADDR_OFFSET], 8);

					__COUT__ << std::hex << ":::"
					         << "Read address: 0x" << std::hex << addr;
					__PRINTF__(" 0x%16.16lX \n", addr);

					// setup response packet based on address
					buff[handlerIndex + 0] = 0;  // read type
					buff[handlerIndex + 1] =
					    sequence++;  // 1-byte sequence id increments and wraps

					switch(addr)  // define address space
					{
					case 0x1001:
						memcpy((void*)&buff[handlerIndex + TX_DATA_OFFSET],
						       (void*)&data_gen_cnt,
						       8);
						__COUT__ << std::hex << ":::"
						         << "Read data count: 0x" << data_gen_cnt << std::endl;
						break;
					case 0x1002:
						memcpy((void*)&buff[handlerIndex + TX_DATA_OFFSET],
						       (void*)&data_gen_rate,
						       8);
						__COUT__ << std::hex << ":::"
						         << "Read data rate: 0x" << data_gen_rate << std::endl;
						break;
					case 0x1003:
						memset((void*)&buff[handlerIndex + TX_DATA_OFFSET + 1], 0, 7);
						memcpy((void*)&buff[handlerIndex + TX_DATA_OFFSET],
						       (void*)&led_register,
						       1);
						__COUT__ << std::hex << ":::"
						         << "Read LED register: 0x" << (unsigned int)led_register
						         << std::endl;
						break;
					case 0x0000000100000006:
						memset((void*)&buff[handlerIndex + TX_DATA_OFFSET + 4], 0, 4);
						memcpy((void*)&buff[handlerIndex + TX_DATA_OFFSET],
						       (void*)&streamToIP_reg,
						       4);
						__COUT__ << std::hex << ":::"
						         << "Read Stream destination IP: " << streamToIP
						         << std::endl;
						break;
					case 0x0000000100000008:
						memset((void*)&buff[handlerIndex + TX_DATA_OFFSET + 4], 0, 4);
						memcpy((void*)&buff[handlerIndex + TX_DATA_OFFSET],
						       (void*)&streamToPort,
						       4);
						__COUT__ << std::hex << ":::"
						         << "Read Stream destination port: 0x" << streamToPort
						         << " (" << std::dec << streamToPort << ")" << std::endl;
						break;
					case 0x0000000100000009:
						memset((void*)&buff[handlerIndex + TX_DATA_OFFSET + 1], 0, 7);
						memcpy((void*)&buff[handlerIndex + TX_DATA_OFFSET],
						       (void*)&dataEnabled,
						       1);
						__COUT__ << std::hex << ":::"
						         << "Read data enable: 0x" << dataEnabled << std::endl;
						break;
					case 0x1004:
						memset((void*)&buff[handlerIndex + TX_DATA_OFFSET + 1], 0, 7);
						memcpy((void*)&buff[handlerIndex + TX_DATA_OFFSET],
						       (void*)&data_mode,
						       1);
						__COUT__ << ":::"
						         << "Read data mode: " << (int)data_mode << std::endl;
						break;
					case 0x1005:
						memset((void*)&buff[handlerIndex + TX_DATA_OFFSET + 2], 0, 6);
						memcpy((void*)&buff[handlerIndex + TX_DATA_OFFSET],
						       (void*)&sample_bit_width,
						       2);
						__COUT__ << ":::"
						         << "Read sample bit width: " << sample_bit_width
						         << std::endl;
						break;
					case 0x1006:
						memset((void*)&buff[handlerIndex + TX_DATA_OFFSET + 2], 0, 6);
						memcpy((void*)&buff[handlerIndex + TX_DATA_OFFSET],
						       (void*)&samples_per_packet,
						       2);
						__COUT__ << ":::"
						         << "Read samples per packet: " << samples_per_packet
						         << std::endl;
						break;
					case 0x1007:
						memset((void*)&buff[handlerIndex + TX_DATA_OFFSET + 2], 0, 6);
						memcpy((void*)&buff[handlerIndex + TX_DATA_OFFSET],
						       (void*)&num_channels,
						       2);
						__COUT__ << ":::"
						         << "Read num channels: " << num_channels << std::endl;
						break;
					case 0x1008:
						memset((void*)&buff[handlerIndex + TX_DATA_OFFSET + 2], 0, 6);
						memcpy((void*)&buff[handlerIndex + TX_DATA_OFFSET],
						       (void*)&wave_period,
						       2);
						__COUT__ << ":::"
						         << "Read wave period: " << wave_period << std::endl;
						break;
					case 0x1009:
						memset((void*)&buff[handlerIndex + TX_DATA_OFFSET + 2], 0, 6);
						memcpy((void*)&buff[handlerIndex + TX_DATA_OFFSET],
						       (void*)&wave_amplitude_pct,
						       2);
						__COUT__ << ":::"
						         << "Read wave amplitude %: " << wave_amplitude_pct
						         << std::endl;
						break;
					case 0x100A:
						memset((void*)&buff[handlerIndex + TX_DATA_OFFSET + 2], 0, 6);
						memcpy((void*)&buff[handlerIndex + TX_DATA_OFFSET],
						       (void*)&wave_offset_pct,
						       2);
						__COUT__ << ":::"
						         << "Read wave offset %: " << wave_offset_pct
						         << std::endl;
						break;
					default:
						__COUT__ << std::hex << ":::"
						         << "Unknown read address received." << std::endl;
					}

					packetSz = TX_DATA_OFFSET + 8;  // only response with 1 QW
					if((numberOfBytes = sendto(sockfd,
					                           buff,
					                           packetSz,
					                           0,
					                           (struct sockaddr*)&their_addr,
					                           sizeof(struct sockaddr_storage))) == -1)
					{
						perror("hw: sendto");
						exit(1);
					}
					__PRINTF__("hw: sent %d bytes back. sequence=%d\n",
					           numberOfBytes,
					           (unsigned char)buff[handlerIndex + 1]);
				}
				else if(numberOfBytes >= 18 &&
				        (numberOfBytes - 2) % 8 ==
				            0 &&  // size is valid (multiple of 8 data)
				        buff[handlerIndex + 0] == 1)  // write
				{
					uint64_t addr;
					memcpy((void*)&addr, (void*)&buff[handlerIndex + RX_ADDR_OFFSET], 8);
					__COUT__ << std::hex << ":::"
					         << "Write address: 0x" << std::hex << addr;
					__PRINTF__(" 0x%16.16lX \n", addr);

					switch(addr)  // define address space
					{
					case 0x1001:
						memcpy((void*)&data_gen_cnt,
						       (void*)&buff[handlerIndex + RX_DATA_OFFSET],
						       8);
						__COUT__ << std::hex << ":::"
						         << "Write data count: 0x" << data_gen_cnt << std::endl;
						count = 0;  // reset count
						break;
					case 0x1002:
						memcpy((void*)&data_gen_rate,
						       (void*)&buff[handlerIndex + RX_DATA_OFFSET],
						       8);
						__COUT__ << std::hex << ":::"
						         << "Write data rate: 0x" << data_gen_rate << std::endl;
						break;
					case 0x1003:
						memcpy((void*)&led_register,
						       (void*)&buff[handlerIndex + RX_DATA_OFFSET],
						       1);
						__COUT__ << std::hex << ":::"
						         << "Write LED register: 0x" << (unsigned int)led_register
						         << std::endl;
						// show "LEDs"
						__COUT__ << "\n\n";
						for(int l = 0; l < 8; ++l)
							__COUT__ << ((led_register & (1 << (7 - l))) ? '*' : '-');
						__COUT__ << "\n\n";
						break;
					case 0x0000000100000006: {
						uint32_t           ip;
						struct sockaddr_in socketAddress;
						memcpy(
						    (void*)&ip, (void*)&buff[handlerIndex + RX_DATA_OFFSET], 4);
						streamToIP_reg = ip;  //save for reads
						ip             = htonl(ip);
						memcpy((void*)&socketAddress.sin_addr, (void*)&ip, 4);
						streamToIP = inet_ntoa(socketAddress.sin_addr);
						__COUT__ << std::hex << ":::"
						         << "Write Stream destination IP: " << streamToIP
						         << std::endl;
						__COUT__ << streamToIP << std::endl;
					}
					break;
					case 0x0000000100000007:
						__COUT__ << std::hex << ":::"
						         << "Destination MAC address ignored!" << std::endl;
						break;
					case 0x0000000100000008: {
						// unsigned int myport;
						memcpy((void*)&streamToPort,
						       (void*)&buff[handlerIndex + RX_DATA_OFFSET],
						       4);
						__COUT__ << std::hex << ":::"
						         << "Write Stream destination port: 0x" << streamToPort
						         << std::dec << " (" << streamToPort << ")" << std::endl;

						close(sendSockfd);
						sendSockfd = 0;
						sendSockfd = makeSocket(streamToIP.c_str(), streamToPort, p);
						if(sendSockfd != -1)
						{
							__COUT__ << "************************************************"
							            "********"
							         << std::endl;
							__COUT__ << "************************************************"
							            "********"
							         << std::endl;
							__COUT__ << std::hex << ":::"
							         << "Streaming to ip: " << streamToIP << " port: 0x"
							         << streamToPort << std::endl;
							__COUT__ << "************************************************"
							            "********"
							         << std::endl;
							__COUT__ << "************************************************"
							            "********"
							         << std::endl;
						}
						else
							__COUT__ << std::hex << ":::"
							         << "Failed to create streaming socket to ip: "
							         << streamToIP << " port: 0x" << streamToPort
							         << std::endl;
					}

					break;
					case 0x0000000100000009:
						memcpy((void*)&dataEnabled,
						       (void*)&buff[handlerIndex + RX_DATA_OFFSET],
						       1);
						__COUT__ << std::hex << ":::"
						         << "Write data enable: 0x" << (int)dataEnabled
						         << std::endl;
						count = 0;  // reset count
						break;
					case 0x1004:
						memcpy((void*)&data_mode,
						       (void*)&buff[handlerIndex + RX_DATA_OFFSET],
						       1);
						__COUT__ << ":::"
						         << "Write data mode: " << (int)data_mode << std::endl;
						break;
					case 0x1005:
						memcpy((void*)&sample_bit_width,
						       (void*)&buff[handlerIndex + RX_DATA_OFFSET],
						       2);
						if(sample_bit_width != 8 && sample_bit_width != 12 &&
						   sample_bit_width != 16 && sample_bit_width != 32)
							sample_bit_width = 16;
						__COUT__ << ":::"
						         << "Write sample bit width: " << sample_bit_width
						         << std::endl;
						break;
					case 0x1006:
						memcpy((void*)&samples_per_packet,
						       (void*)&buff[handlerIndex + RX_DATA_OFFSET],
						       2);
						__COUT__ << ":::"
						         << "Write samples per packet: " << samples_per_packet
						         << std::endl;
						break;
					case 0x1007:
						memcpy((void*)&num_channels,
						       (void*)&buff[handlerIndex + RX_DATA_OFFSET],
						       2);
						if(num_channels == 0)
							num_channels = 1;
						__COUT__ << ":::"
						         << "Write num channels: " << num_channels << std::endl;
						break;
					case 0x1008:
						memcpy((void*)&wave_period,
						       (void*)&buff[handlerIndex + RX_DATA_OFFSET],
						       2);
						__COUT__ << ":::"
						         << "Write wave period: " << wave_period << std::endl;
						break;
					case 0x1009:
						memcpy((void*)&wave_amplitude_pct,
						       (void*)&buff[handlerIndex + RX_DATA_OFFSET],
						       2);
						if(wave_amplitude_pct > 1000)  // allow >100% to show clipping
							wave_amplitude_pct = 1000;
						__COUT__ << ":::"
						         << "Write wave amplitude %: " << wave_amplitude_pct
						         << std::endl;
						break;
					case 0x100A:
						memcpy((void*)&wave_offset_pct,
						       (void*)&buff[handlerIndex + RX_DATA_OFFSET],
						       2);
						if(wave_offset_pct > 100)
							wave_offset_pct = 100;
						__COUT__ << ":::"
						         << "Write wave offset %: " << wave_offset_pct
						         << std::endl;
						break;
					default:
						__COUT__ << std::hex << ":::"
						         << "Unknown write address received." << std::endl;
					}
				}
				else
					__COUT__ << std::hex << ":::"
					         << "ERROR: The formatting of the string received is wrong! "
					            "Number of bytes: "
					         << numberOfBytes << " Read/Write " << buff[handlerIndex + 0]
					         << std::endl;

				handlerIndex += numberOfBytes;
			}

			__COUT__ << std::hex << ":::"
			         << "\n\n"
			         << addressSpaceSS.str() << "\n\n";

		}  // end packet received if
		else
		{
			// no packet received (timeout)

			//__COUT__ << "[" << __LINE__ << "]Is burst enabled? " << (int)dataEnabled <<
			// endl;
			if((int)dataEnabled)
			{
				// generate data
				//__COUT__ << "[" << __LINE__ << "]Count? " << count << " rate: " <<
				// data_gen_rate << " counter: " << data_gen_cnt << endl;
				if(count % data_gen_rate == 0 &&  // if delayed enough for proper rate
				   data_gen_cnt != 0)             // still packets to send
				{
					// if(count%0x100000 == 0)
					__COUT__ << std::hex << ":::"
					         << "Count: 0x" << count << " rate: 0x" << data_gen_rate
					         << " packet-counter: 0x" << data_gen_cnt << std::endl;
					__COUT__ << std::hex << ":::"
					         << "Send Burst at count: 0x" << count << std::endl;
					// send a packet
					buff[0] =
					    wasDataSent ? 2 : 1;  // type := burst middle (2) or first (1)
					buff[1]  = sequence++;    // 1-byte sequence id increments and wraps
					packetSz = fillBurstPayload(buff,
					                            TX_DATA_OFFSET,
					                            data_mode,
					                            sample_bit_width,
					                            samples_per_packet,
					                            num_channels,
					                            wave_period,
					                            wave_amplitude_pct,
					                            wave_offset_pct,
					                            count);

					if((numberOfBytes = sendto(
					        sendSockfd, buff, packetSz, 0, p->ai_addr, p->ai_addrlen)) ==
					   -1)
					{
						perror("Hw: sendto error!");
						exit(1);
					}
					__PRINTF__("hw: Sent %d streaming bytes. sequence=%d\n",
					           numberOfBytes,
					           (unsigned char)buff[1]);

					if(data_gen_cnt != (uint64_t)-1)
						--data_gen_cnt;

					wasDataSent = true;
				}

				wasDataEnabled = true;
			}
			else if(wasDataEnabled)  // send last in burst packet
			{
				wasDataSent = wasDataEnabled = false;
				__COUT__ << std::hex << ":::"
				         << "Send Last in Burst at count:" << count << std::endl;
				// send a packet
				buff[0]  = 3;           // type := burst last (3)
				buff[1]  = sequence++;  // 1-byte sequence id increments and wraps
				packetSz = fillBurstPayload(buff,
				                            TX_DATA_OFFSET,
				                            data_mode,
				                            sample_bit_width,
				                            samples_per_packet,
				                            num_channels,
				                            wave_period,
				                            wave_amplitude_pct,
				                            wave_offset_pct,
				                            count);

				if(sendSockfd != -1)
				{
					if((numberOfBytes = sendto(
					        sendSockfd, buff, packetSz, 0, p->ai_addr, p->ai_addrlen)) ==
					   -1)
					{
						perror("hw: sendto error!");
						exit(1);
					}
					__PRINTF__("hw: Sent %d closing bytes. sequence=%d\n",
					           numberOfBytes,
					           (unsigned char)buff[1]);
				}
				else
					__COUT__ << std::hex << ":::"
					         << "Send socket not defined." << std::endl;
			}

			++count;
		}
	}  // end main loop

	close(sockfd);

	return 0;
}
