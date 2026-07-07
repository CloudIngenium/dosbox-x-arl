/*
 *  Copyright (C) 2002-2021  The DOSBox Team
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License along
 *  with this program; if not, write to the Free Software Foundation, Inc.,
 *  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
 */


// include guard
#ifndef DOSBOX_DIRECTSERIAL_WIN32_H
#define DOSBOX_DIRECTSERIAL_WIN32_H

#include "dosbox.h"

#if C_DIRECTSERIAL

#include <cstdio>
#include <string>

#define DIRECTSERIAL_AVAILIBLE
#include "serialport.h"

#include "libserial.h"

class CDirectSerial : public CSerial {
public:
	CDirectSerial(Bitu id, CommandLine* cmd);
	~CDirectSerial();

	void updatePortConfig(uint16_t divider, uint8_t lcr) override;
	void updateMSR() override;
	void transmitByte(uint8_t val, bool first) override;
	void setBreak(bool value) override;
	
	void setRTSDTR(bool rts, bool dtr) override;
	void setRTS(bool val) override;
	void setDTR(bool val) override;
	void handleUpperEvent(uint16_t type) override;

private:
	COMPORT comport;

	Bitu rx_state = 0;
#define D_RX_IDLE		0
#define D_RX_WAIT		1
#define D_RX_BLOCKED	2
#define D_RX_FASTWAIT	3

	Bitu rx_retry;		// counter of retries (every millisecond)
	Bitu rx_retry_max;	// how many POLL_EVENTS to wait before causing
						// an overrun error.
	bool doReceive();

	std::string realport_name;
	std::string arltrace_path;
	FILE *arltrace_fp = nullptr;
	uint32_t arltrace_start_tick = 0;

	int trace_baudrate = 0;
	uint8_t trace_bytelength = 0;
	uint8_t trace_stopbits = SERIAL_1STOP;
	char trace_parity = 'n';
	bool trace_rts = false;
	bool trace_dtr = false;
	bool trace_break = false;
	int trace_modem_status = -1;

	void traceOpen(const std::string &path);
	void traceCommonFields(const char *event);
	void traceJsonString(const char *value);
	void traceMessage(const char *event, const char *message);
	void traceByte(const char *event, uint8_t val, uint8_t error);
	void traceConfig(int baudrate, char parity, uint8_t stopbits,
	                 uint8_t bytelength, bool accepted);
	void traceModemStatus(int status);
	void traceControlLines(const char *event);
	const char *traceAscii(uint8_t val, char *buffer, size_t buffer_size);

#if SERIAL_DEBUG
	bool dbgmsg_poll_block = false;
	bool dbgmsg_rx_block = false;
#endif

};

#endif	// C_DIRECTSERIAL
#endif	// include guard
