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
#include <deque>
#include <string>
#include <vector>

#define DIRECTSERIAL_AVAILIBLE
#include "serialport.h"
#include "arl_result_corrector.h"

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
	bool arlTraceIsEnabled() const override;
	std::string arlTraceStatus() override;
	void arlTraceMark(const char *message) override;
	bool arlTraceRotate() override;
	void arlTraceUartEvent(const char *direction, const char *reg,
	                       Bitu port, uint8_t value,
	                       const SerialTraceSnapshot &snapshot) override;

private:
	enum ArlTraceLevel {
		ARL_TRACE_BASIC = 0,
		ARL_TRACE_UARTDATA = 1,
		ARL_TRACE_UART = 2,
		ARL_TRACE_FULL = 3
	};

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
	std::string arltrace_session;
	FILE *arltrace_fp = nullptr;
	uint32_t arltrace_start_tick = 0;
	uint32_t arltrace_last_io_tick = 0;
	uint32_t arltrace_last_hang_tick = 0;
	Bitu arltrace_hang_ms = 0;
	unsigned long long arltrace_max_bytes = 0;
	bool arltrace_limit_reached = false;
	ArlTraceLevel arltrace_level = ARL_TRACE_BASIC;

	int trace_baudrate = 0;
	uint8_t trace_bytelength = 0;
	uint8_t trace_stopbits = SERIAL_1STOP;
	char trace_parity = 'n';
	bool trace_rts = false;
	bool trace_dtr = false;
	bool trace_break = false;
	int trace_modem_status = -1;
	bool arl_force_cts = false;
	bool arl_force_dsr = false;
	bool arl_force_dcd = false;
	bool arl_hold_rts = false;
	bool arl_hold_dtr = false;
	bool arl_result_observe = false;
	bool arl_result_retry_low = false;
	bool arl_awaiting_result = false;
	bool arl_retry_correction_pending = false;
	bool arl_retry_blocked = false;
	bool arl_current_result_mutated = false;
	bool arl_last_result_mutated = false;
	ArlResultCorrector arl_result_corrector;
	std::string arl_tx_frame;
	std::string arl_rx_frame;
	std::string arl_retry_host_frame;
	std::deque<uint8_t> arl_retry_guest_bytes;
	int arl_last_claimed_checksum = -1;
	int arl_last_computed_checksum = -1;
	int arl_physical_result_checksum = -1;
	bool trace_have_tx = false;
	bool trace_have_rx = false;
	uint8_t trace_last_tx = 0;
	uint8_t trace_last_rx = 0;
	uint8_t trace_last_rx_error = 0;
	Bitu trace_tx_count = 0;
	Bitu trace_rx_count = 0;
	Bitu trace_tx_errors = 0;
	std::string trace_last_error;

	void traceOpen(const std::string &path);
	bool traceOpenCurrentPath();
	void traceCommonFields(const char *event);
	void traceFlush();
	void traceCheckLimit();
	void traceJsonString(const char *value);
	void traceMessage(const char *event, const char *message);
	void traceByte(const char *event, uint8_t val, uint8_t error);
	void traceConfig(int baudrate, char parity, uint8_t stopbits,
	                 uint8_t bytelength, bool accepted);
	void traceModemStatus(int status);
	void traceControlLines(const char *event);
	void traceSnapshot(const char *event, const SerialTraceSnapshot &snapshot);
	void traceHostState(const char *event);
	void traceHangSnapshot();
	void observeTxByte(uint8_t val);
	void observeRxByte(uint8_t val);
	void handleRejectedResult();
	void traceObservedResult(const std::string &frame);
	void traceObservedDecision(const char *decision);
	bool buildEquivalentResult(const std::string &frame, std::string &presented,
	                           int &target_checksum);
	void traceResultCorrection(const std::string &original,
	                           const std::string &presented,
	                           int original_checksum,
	                           int presented_checksum,
	                           const char *reason);
	std::string traceRotatePath() const;
	const char *traceLevelName() const;
	const char *traceAscii(uint8_t val, char *buffer, size_t buffer_size);

#if SERIAL_DEBUG
	bool dbgmsg_poll_block = false;
	bool dbgmsg_rx_block = false;
#endif

};

#endif	// C_DIRECTSERIAL
#endif	// include guard
