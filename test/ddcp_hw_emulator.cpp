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
#include <iomanip>
#include <iostream>
#include <sstream>
#include <string>

/// take only file name
#define __FILENAME__ (strrchr(__FILE__, '/') ? strrchr(__FILE__, '/') + 1 : __FILE__)

/// use this for normal printouts
#define __PRINTF__ printf
#define __COUT__ std::cout << __FILENAME__ << std::dec << " [" << __LINE__ << "]\t"

/// and use this to suppress
///#define __PRINTF__ if(0) printf
///#define __COUT__  if(0) cout
///
#define MAXBUFLEN 1500         // 1492
#define EMULATOR_PORT "65000"  // Can be also passed as first argument

/// get sockaddr, IPv4 or IPv6:
void* get_in_addr(struct sockaddr* sa)
{
	if(sa->sa_family == AF_INET)
	{
		return &(((struct sockaddr_in*)sa)->sin_addr);
	}

	return &(((struct sockaddr_in6*)sa)->sin6_addr);
}  // end get_in_addr()

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
}  // end makeSocket()

uint64_t my_ntohll(char* buff)
{
	uint64_t v = 0;
	for(unsigned int i = 0; i < 8; ++i)
		v |= (unsigned char)buff[7 - i] << (i * 8);
	return v;
}  // end my_ntohll()

void my_htonll(uint64_t v, char* buff)
{
	for(unsigned int i = 0; i < 8; ++i)
		buff[7 - i] = v >> (i * 8);

}  // end my_htonll()

int main(int argc, char** argv)
{
	std::string emulatorPort(EMULATOR_PORT);
	if(argc == 2)
		emulatorPort = argv[1];

	__COUT__ << std::hex << ":::"
	         << "\n\nUsing emulatorPort=" << emulatorPort << "\n"
	         << std::endl;

	std::string streamToIP;
	uint32_t    streamToPort;

	int                     sockfd;
	int                     sendSockfd = 0;
	struct addrinfo         hints, *servinfo, *p;
	int                     rv;
	uint64_t                numberOfBytes, numberOfSentBytes;
	struct sockaddr_storage their_addr;
	char                    buff[MAXBUFLEN];
	char                    respbuff[MAXBUFLEN];
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

	__COUT__ << addressSpaceSS.str() << "\n\n";

	// hardware "registers"
	uint64_t data_gen_cnt  = 0;
	uint64_t data_gen_rate = 100;  // number of loops to wait
	uint8_t  led_register  = 0;
	uint8_t  dataEnabled   = 0;

	const unsigned int RX_ADDR_OFFSET = 2;
	const unsigned int RX_DATA_OFFSET = 10;
	const unsigned int TX_DATA_OFFSET = 2;

	bool          wasDataEnable = false;
	unsigned char sequence      = 0;
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

	if(emulatorPort != EMULATOR_PORT)
	{
		__COUT__ << "DDCP Client Port... so initiating Interrupt Request" << std::endl;

		// create interrupt request packet
		my_htonll(0x0002000000000010,
		          &respbuff[0]);  // version (16b) | slot (16b) | feature (16b) | op (16b)
		my_htonll(0x0, &respbuff[8]);   // status (16b) | reserved
		my_htonll(0x0, &respbuff[16]);  // index
		my_htonll(0x1, &respbuff[24]);  // count
		my_htonll(0x4, &respbuff[32]);  // payload size = 4B = 32b
		my_htonll(
		    0x000A000500000000,
		    &respbuff[40]);  // interrupt source slot 16b | 11b X | source interrupt 5b
		packetSz = 44;

		// create destination socket at localhost port 65000
		{
			uint32_t           ip = (127 << 24) | 1;  // localhost
			struct sockaddr_in socketAddress;
			ip = htonl(ip);
			memcpy((void*)&socketAddress.sin_addr, (void*)&ip, 4);
			streamToIP = inet_ntoa(socketAddress.sin_addr);
			__COUT__ << std::hex << ":::"
			         << "Stream destination IP: " << streamToIP << std::endl;
			__COUT__ << streamToIP << std::endl;
		}

		// create destination port
		{
			// unsigned int myport;
			streamToPort = 65000;

			__COUT__ << std::hex << ":::"
			         << "Stream destination port: 0x" << streamToPort << std::dec << " "
			         << streamToPort << std::endl;

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
				         << "Failed to create streaming socket to ip: " << streamToIP
				         << " port: 0x" << streamToPort << std::endl;
		}

		if((numberOfSentBytes = sendto(
		        sendSockfd, respbuff, packetSz, 0, p->ai_addr, p->ai_addrlen)) == -1)
		{
			perror("hw: sendto");
			exit(1);
		}
		__PRINTF__("hw: Interrupt Req packet sent %d bytes back\n", numberOfSentBytes);

		for(int i = 0; i < numberOfSentBytes; i++)
		{
			if(i % 8 == 0)
				__COUT__ << "\t" << i << " \t";
			__PRINTF__("%2.2X", (unsigned char)respbuff[i]);
			if(i % 8 == 7)
				std::cout << std::endl;
		}
		std::cout << std::endl;
		__COUT__ << "Waiting for ack..." << std::endl;

		addr_len = sizeof their_addr;
		if((totalNumberOfBytes = recvfrom(sendSockfd,
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
		__COUT__ << ":::"
		         << "hw: packet contents \n";
		for(int i = 0; i < totalNumberOfBytes; i++)
		{
			if(i % 8 == 0)
				__COUT__ << "\t" << i << " \t";
			__PRINTF__("%2.2X", (unsigned char)buff[i]);
			if(i % 8 == 7)
				std::cout << std::endl;
		}
		std::cout << std::endl;

	}  // end Interrupt Request handling

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
			__COUT__ << ":::"
			         << "hw: packet contents \n";
			for(int i = 0; i < totalNumberOfBytes; i++)
			{
				if(i % 8 == 0)
					__COUT__ << "\t" << i << " \t";
				__PRINTF__("%2.2X", (unsigned char)buff[i]);
				if(i % 8 == 7)
					std::cout << std::endl;

				//				//__COUT__ << std::hex << std::setw(2) << (int)(unsigned
				// char)buff[i] << std::dec;
			}

			// treat as stacked packets
			handlerIndex = 0;

			// while another packet, handle
			while(handlerIndex + 40 <= totalNumberOfBytes &&
			      (numberOfBytes = 40 + my_ntohll(&buff[handlerIndex + 32])) &&
			      handlerIndex + numberOfBytes <= totalNumberOfBytes)
			{
				__COUT__ << ":::"
				         << "hw: packet byte index " << handlerIndex << std::endl;
				__COUT__ << ":::"
				         << "hw: packet is " << numberOfBytes << " bytes long"
				         << std::endl;

				uint16_t version      = ntohs(*((uint16_t*)&(buff[handlerIndex + 0])));
				uint16_t slot         = ntohs(*((uint16_t*)&(buff[handlerIndex + 2])));
				uint16_t feature      = ntohs(*((uint16_t*)&(buff[handlerIndex + 4])));
				uint16_t operation    = ntohs(*((uint16_t*)&(buff[handlerIndex + 6])));
				int16_t  status       = ntohs(*((uint16_t*)&(buff[handlerIndex + 8])));
				uint64_t index        = my_ntohll(&(buff[handlerIndex + 16]));
				uint64_t count        = my_ntohll(&(buff[handlerIndex + 24]));
				uint64_t payloadBytes = numberOfBytes - 40;

				uint64_t responsePacketCount = 0;

				__COUT__ << "version      (16b) = \t" << version << "\t 0x" << std::hex
				         << version << std::dec << std::endl;
				__COUT__ << "slot         (16b) = \t" << slot << "\t 0x" << std::hex
				         << slot << std::dec << std::endl;
				__COUT__ << "feature      (16b) = \t" << feature << "\t 0x" << std::hex
				         << feature << std::dec << std::endl;
				__COUT__ << "operation    (16b) = \t" << operation << "\t 0x" << std::hex
				         << operation << std::dec << std::endl;
				__COUT__ << "status       (16b) = \t" << status << "\t 0x" << std::hex
				         << status << std::dec << std::endl;
				__COUT__ << "index        (64b) = \t" << index << "\t 0x" << std::hex
				         << index << std::dec << std::endl;
				__COUT__ << "count        (64b) = \t" << count << "\t 0x" << std::hex
				         << count << std::dec << std::endl;
				__COUT__ << "payloadBytes (64b) = \t" << payloadBytes << "\t 0x"
				         << std::hex << payloadBytes << std::dec << std::endl;

				// handlerIndex += numberOfBytes;
				// continue;

				// handle packet
				if(payloadBytes == 0 &&  // size is valid (type, size, 8-byte address)
				   operation == 2)       // read
				{
					__COUT__ << "Read! " << std::endl;
					memcpy((void*)respbuff, (void*)&buff[handlerIndex], 40);

					uint64_t addr  = (feature << 24) | index;
					uint64_t rdata = 0;
					payloadBytes   = 0;  // use to count

					// read location for each count
					for(uint64_t i = 0; i < count; ++i)
					{
						switch(addr)  // define address space
						{
						case 0x1001:
							rdata = data_gen_cnt;

							__COUT__ << std::hex << ":::"
							         << "Read data count: 0x" << data_gen_cnt
							         << std::endl;
							break;
						case 0x1002:
							rdata = data_gen_rate;

							__COUT__ << std::hex << ":::"
							         << "Read data rate: 0x" << data_gen_rate
							         << std::endl;
							break;
						case 0x1003:
							rdata = led_register;

							__COUT__ << std::hex << ":::"
							         << "Read LED register: 0x"
							         << (unsigned int)led_register << std::endl;
							break;
						case 0x0000000100000009:
							rdata = dataEnabled;

							__COUT__ << std::hex << ":::"
							         << "Read data enable: 0x" << dataEnabled
							         << std::endl;
							break;
						default:
							rdata = addr + i;

							__COUT__ << std::hex << ":::" << addr
							         << " -- Unknown read address received for count "
							         << std::dec << i << std::endl;
						}

						if(40 + payloadBytes + 8 > MAXBUFLEN)
						{
							// send partial response packet

							my_htonll(
							    payloadBytes,
							    &respbuff[32]);  // update EXPECTED payload bytes size
							my_htonll(payloadBytes / 8,
							          &respbuff[24]);         // update count bytes size
							my_htonll(index, &respbuff[16]);  // update index
							packetSz =
							    40 + payloadBytes;  // update total respsone size in bytes

							if((numberOfSentBytes =
							        sendto(sockfd,
							               respbuff,
							               packetSz,
							               0,
							               (struct sockaddr*)&their_addr,
							               sizeof(struct sockaddr_storage))) == -1)
							{
								perror("hw: sendto");
								exit(1);
							}
							__PRINTF__(
							    "hw: Resp packet #%d index=%d sent %d bytes back\n",
							    responsePacketCount,
							    index,
							    numberOfSentBytes);

							for(int b = 0; b < numberOfSentBytes; b++)
							{
								if(b % 8 == 0)
									__COUT__ << "\t" << b << " \t";
								__PRINTF__("%2.2X", (unsigned char)respbuff[b]);
								if(b % 8 == 7)
									std::cout << std::endl;
							}

							index += payloadBytes / 8;
							payloadBytes = 0;

							++responsePacketCount;
							// usleep(3000000);
						}

						my_htonll(rdata, &respbuff[40 + payloadBytes]);  // insert data QW
						payloadBytes += 8;
					}  // end read count loop

					// my_htonll(0xa00010002,&respbuff[0]); //update EXPECTED payload
					// bytes size
					my_htonll(payloadBytes,
					          &respbuff[32]);  // update EXPECTED payload bytes size
					my_htonll(payloadBytes / 8, &respbuff[24]);  // update count bytes
					                                             // size
					my_htonll(index, &respbuff[16]);             // update index

					// my_htonll(count*8,&respbuff[32]); //update EXPECTED payload bytes
					// size
					packetSz = 40 + payloadBytes;  // update total respsone size in bytes

					// my_htonll(payloadBytes,&respbuff[32]); //update payload bytes size
					// packetSz = 40 + payloadBytes;  // update total respsone size in
					// bytes

					if((numberOfSentBytes = sendto(sockfd,
					                               respbuff,
					                               packetSz,
					                               0,
					                               (struct sockaddr*)&their_addr,
					                               sizeof(struct sockaddr_storage))) ==
					   -1)
					{
						perror("hw: sendto");
						exit(1);
					}
					__PRINTF__("hw: Resp packet #%d index=%d sent %d bytes back\n",
					           responsePacketCount,
					           index,
					           numberOfSentBytes);

					for(int i = 0; i < numberOfSentBytes; i++)
					{
						if(i % 8 == 0)
							__COUT__ << "\t" << i << " \t";
						__PRINTF__("%2.2X", (unsigned char)respbuff[i]);
						if(i % 8 == 7)
							std::cout << std::endl;
					}

				}  // end READ handling
				   // =====================================================
				else if(payloadBytes % 8 == 0 && count == payloadBytes / 8 &&
				        operation == 4)  // write
				{
					__COUT__ << "Write!" << std::endl;
					memcpy((void*)respbuff, (void*)&buff[handlerIndex], 40);

					uint64_t addr = feature | (index << 16);
					uint64_t wdata;

					// write location for each count
					for(uint64_t i = 0; i < count; ++i)
					{
						wdata = my_ntohll(&buff[handlerIndex + 40 + i * 8]);
						__COUT__ << ":::"
						         << "Count #" << i << "Write data = " << wdata << "\t 0x"
						         << std::hex << wdata << std::endl;

						switch(addr)  // define address space
						{
						case 0x1001:

							data_gen_cnt = wdata;
							__COUT__ << std::hex << ":::"
							         << "Write data count: 0x" << data_gen_cnt
							         << std::endl;
							count = 0;  // reset count
							break;
						case 0x1002:
							data_gen_rate = wdata;

							__COUT__ << std::hex << ":::"
							         << "Write data rate: 0x" << data_gen_rate
							         << std::endl;
							break;
						case 0x1003:
							led_register = wdata;

							__COUT__ << std::hex << ":::"
							         << "Write LED register: 0x"
							         << (unsigned int)led_register << std::endl;
							// show "LEDs"
							__COUT__ << "\n\n";
							for(int l = 0; l < 8; ++l)
								__COUT__ << ((led_register & (1 << (7 - l))) ? '*' : '-');
							__COUT__ << "\n\n";
							break;

						case 0x0000000100000009:
							dataEnabled = wdata;

							__COUT__ << std::hex << ":::"
							         << "Write data enable: 0x" << (int)dataEnabled
							         << std::endl;
							count = 0;  // reset count
							break;
						default:
							__COUT__ << std::hex << "::: 0x" << addr
							         << " -- Unknown write address received."
							         << std::endl;
						}
					}  // end write count loop

					// now send ack packet
					my_htonll(0, &respbuff[32]);
					packetSz = 40;

					if((numberOfSentBytes = sendto(sockfd,
					                               respbuff,
					                               packetSz,
					                               0,
					                               (struct sockaddr*)&their_addr,
					                               sizeof(struct sockaddr_storage))) ==
					   -1)
					{
						perror("hw: sendto");
						exit(1);
					}
					__PRINTF__("hw: sent %d bytes back\n", numberOfSentBytes);

					for(int i = 0; i < numberOfSentBytes; i++)
					{
						if(i % 8 == 0)
							__COUT__ << "\t" << i << " \t";
						__PRINTF__("%2.2X", (unsigned char)respbuff[i]);
						if(i % 8 == 7)
							std::cout << std::endl;
					}

				}  // end WRITE handling
				   // ==================================================
				else if(payloadBytes == 0 && operation == 1 << 0)  // query
				{
					__COUT__ << "Query!" << std::endl;
					memcpy((void*)respbuff, (void*)&buff[handlerIndex], 40);

					// respond with query object {
					//  8B ops mask,
					//  8B element bytes (always 64b/8B from firmware)
					//  8B number of elements (number of sub-features?)

					// return query, read, set support
					my_htonll((1 << 0) | (1 << 1) | (1 << 2),
					          &respbuff[40 + payloadBytes]);  // insert data QW
					payloadBytes += 8;
					// return quad word elements
					my_htonll(8, &respbuff[40 + payloadBytes]);  // insert data QW
					payloadBytes += 8;
					// return 1 sub-feature
					my_htonll(1, &respbuff[40 + payloadBytes]);  // insert data QW
					payloadBytes += 8;

					my_htonll(payloadBytes, &respbuff[32]);  // update payload bytes size
					packetSz = 40 + payloadBytes;  // update total respsone size in bytes

					if((numberOfSentBytes = sendto(sockfd,
					                               respbuff,
					                               packetSz,
					                               0,
					                               (struct sockaddr*)&their_addr,
					                               sizeof(struct sockaddr_storage))) ==
					   -1)
					{
						perror("hw: sendto");
						exit(1);
					}
					__PRINTF__("hw: sent %d bytes back\n", numberOfSentBytes);

					for(int i = 0; i < numberOfSentBytes; i++)
					{
						if(i % 8 == 0)
							__COUT__ << "\t" << i << " \t";
						__PRINTF__("%2.2X", (unsigned char)respbuff[i]);
						if(i % 8 == 7)
							std::cout << std::endl;
					}

				}  // end QUERY handling
				   // =====================================================
				else
					__COUT__ << ":::"
					         << "ERROR: The formatting of the packet received is wrong! "
					         << "Number of bytes: " << numberOfBytes << " Operation "
					         << operation << std::endl;

				handlerIndex += numberOfBytes;
			}  // end sub-packet operation loop

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
					         << "Count: " << count << " rate: " << data_gen_rate
					         << " packet-counter: " << data_gen_cnt << std::endl;
					__COUT__ << std::hex << ":::"
					         << "Send Burst at count:" << count << std::endl;
					// send a packet
					buff[0] =
					    wasDataEnable ? 2 : 1;  // type := burst middle (2) or first (1)
					buff[1] = sequence++;       // 1-byte sequence id increments and wraps
					memcpy((void*)&buff[TX_DATA_OFFSET],
					       (void*)&count,
					       8);  // make data counter
					// memcpy((void *)&buff[TX_DATA_OFFSET],(void *)&data_gen_cnt,8);
					// //make data counter

					packetSz = TX_DATA_OFFSET + 8;  // only response with 1 QW
					// packetSz = TX_DATA_OFFSET + 180; //only response with 1 QW
					//	    			__COUT__ << packetSz << std::endl;
					//	    			std::string data(buff,packetSz);
					//	    			unsigned long long value;
					//	    			memcpy((void *)&value, (void *)
					// data.substr(2).data(),8); //make data counter
					//	    			__COUT__ << value << std::endl;

					if((numberOfBytes = sendto(
					        sendSockfd, buff, packetSz, 0, p->ai_addr, p->ai_addrlen)) ==
					   -1)
					{
						perror("Hw: sendto");
						exit(1);
					}
					__PRINTF__("hw: sent %d bytes back. sequence=%d\n",
					           numberOfBytes,
					           (unsigned char)buff[1]);

					if(data_gen_cnt != (uint64_t)-1)
						--data_gen_cnt;
				}

				wasDataEnable = true;
			}
			else if(wasDataEnable)  // send last in burst packet
			{
				wasDataEnable = false;
				__COUT__ << std::hex << ":::"
				         << "Send Last in Burst at count:" << count << std::endl;
				// send a packet
				buff[0] = 3;           // type := burst last (3)
				buff[1] = sequence++;  // 1-byte sequence id increments and wraps
				memcpy(
				    (void*)&buff[TX_DATA_OFFSET], (void*)&count, 8);  // make data counter

				packetSz = TX_DATA_OFFSET + 8;  // only response with 1 QW

				if(sendSockfd != -1)
				{
					if((numberOfBytes = sendto(
					        sendSockfd, buff, packetSz, 0, p->ai_addr, p->ai_addrlen)) ==
					   -1)
					{
						perror("hw: sendto");
						exit(1);
					}
					__PRINTF__("hw: sent %d bytes back. sequence=%d\n",
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
