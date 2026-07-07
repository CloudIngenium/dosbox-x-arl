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


#include "dosbox.h"

#if C_DIRECTSERIAL

#include "logging.h"
#include "serialport.h"
#include "directserial.h"
#include "misc_util.h"
#include "pic.h"
#include "timer.h"

#include "libserial.h"

#include <ctime>
#include <cstring>

/* This is a serial passthrough class.  Its amazingly simple to */
/* write now that the serial ports themselves were abstracted out */

void CDirectSerial::traceOpen(const std::string &path)
{
	arltrace_path = path;
	arltrace_start_tick = GetTicks();
	arltrace_fp = fopen(arltrace_path.c_str(), "ab");
	if (!arltrace_fp) {
		LOG_MSG("Serial%d: ARL trace file \"%s\" could not be opened.",
		        (int)COMNUMBER, arltrace_path.c_str());
		return;
	}

	traceMessage("trace_open", "ARL directserial trace enabled");
}

void CDirectSerial::traceJsonString(const char *value)
{
	fputc('"', arltrace_fp);
	if (value) {
		for (const unsigned char *p = (const unsigned char *)value; *p; p++) {
			switch (*p) {
			case '\\': fputs("\\\\", arltrace_fp); break;
			case '"':  fputs("\\\"", arltrace_fp); break;
			case '\b': fputs("\\b", arltrace_fp); break;
			case '\f': fputs("\\f", arltrace_fp); break;
			case '\n': fputs("\\n", arltrace_fp); break;
			case '\r': fputs("\\r", arltrace_fp); break;
			case '\t': fputs("\\t", arltrace_fp); break;
			default:
				if (*p < 0x20) fprintf(arltrace_fp, "\\u%04x", (unsigned)*p);
				else fputc((int)*p, arltrace_fp);
				break;
			}
		}
	}
	fputc('"', arltrace_fp);
}

void CDirectSerial::traceCommonFields(const char *event)
{
	const uint32_t now = GetTicks();
	const uint32_t elapsed_ms = now - arltrace_start_tick;
	const long long epoch_ms = (long long)time(nullptr) * 1000LL;

	fprintf(arltrace_fp,
	        "{\"epoch_ms\":%lld,\"elapsed_ms\":%u,\"pic_ms\":%.3f,"
	        "\"guest_com\":\"COM%d\",\"serial\":%d,\"realport\":",
	        epoch_ms, (unsigned int)elapsed_ms, (double)PIC_FullIndex(),
	        (int)COMNUMBER, (int)COMNUMBER);
	traceJsonString(realport_name.c_str());
	fputs(",\"event\":", arltrace_fp);
	traceJsonString(event);
}

void CDirectSerial::traceMessage(const char *event, const char *message)
{
	if (!arltrace_fp) return;

	traceCommonFields(event);
	fputs(",\"message\":", arltrace_fp);
	traceJsonString(message);
	fputs("}\n", arltrace_fp);
	fflush(arltrace_fp);
}

const char *CDirectSerial::traceAscii(uint8_t val, char *buffer, size_t buffer_size)
{
	if (buffer_size < 2) return "";

	switch (val) {
	case '\r': strncpy(buffer, "\\r", buffer_size); break;
	case '\n': strncpy(buffer, "\\n", buffer_size); break;
	case '\t': strncpy(buffer, "\\t", buffer_size); break;
	case 0x00: strncpy(buffer, "\\0", buffer_size); break;
	default:
		buffer[0] = (val >= 0x20 && val <= 0x7e) ? (char)val : '.';
		buffer[1] = 0;
		break;
	}
	buffer[buffer_size - 1] = 0;
	return buffer;
}

void CDirectSerial::traceByte(const char *event, uint8_t val, uint8_t error)
{
	if (!arltrace_fp) return;

	char ascii[8];
	traceCommonFields(event);
	fprintf(arltrace_fp,
	        ",\"baud\":%d,\"data_bits\":%u,\"parity\":\"%c\","
	        "\"stop_bits\":%u,\"byte_dec\":%u,\"byte_hex\":\"%02X\","
	        "\"ascii\":",
	        trace_baudrate, (unsigned int)trace_bytelength, trace_parity,
	        (unsigned int)trace_stopbits, (unsigned int)val, (unsigned int)val);
	traceJsonString(traceAscii(val, ascii, sizeof(ascii)));
	fprintf(arltrace_fp,
	        ",\"rx_error_bits\":%u,\"rx_break\":%s,\"rx_framing\":%s,"
	        "\"rx_parity\":%s,\"rx_overrun\":%s,\"rts\":%s,\"dtr\":%s,"
	        "\"cts\":%s,\"dsr\":%s,\"dcd\":%s,\"ri\":%s,\"break\":%s}\n",
	        (unsigned int)error,
	        (error & SERIAL_BREAK_ERR) ? "true" : "false",
	        (error & SERIAL_FRAMING_ERR) ? "true" : "false",
	        (error & SERIAL_PARITY_ERR) ? "true" : "false",
	        (error & SERIAL_OVERRUN_ERR) ? "true" : "false",
	        trace_rts ? "true" : "false",
	        trace_dtr ? "true" : "false",
	        getCTS() ? "true" : "false",
	        getDSR() ? "true" : "false",
	        getCD() ? "true" : "false",
	        getRI() ? "true" : "false",
	        trace_break ? "true" : "false");
	fflush(arltrace_fp);
}

void CDirectSerial::traceConfig(int baudrate, char parity, uint8_t stopbits,
                                uint8_t bytelength, bool accepted)
{
	trace_baudrate = baudrate;
	trace_parity = parity;
	trace_stopbits = stopbits;
	trace_bytelength = bytelength;

	if (!arltrace_fp) return;

	traceCommonFields("config");
	fprintf(arltrace_fp,
	        ",\"baud\":%d,\"data_bits\":%u,\"parity\":\"%c\","
	        "\"stop_bits\":%u,\"accepted\":%s}\n",
	        trace_baudrate, (unsigned int)trace_bytelength, trace_parity,
	        (unsigned int)trace_stopbits, accepted ? "true" : "false");
	fflush(arltrace_fp);
}

void CDirectSerial::traceModemStatus(int status)
{
	if (status == trace_modem_status) return;
	trace_modem_status = status;

	if (!arltrace_fp) return;

	traceCommonFields("modem");
	fprintf(arltrace_fp,
	        ",\"cts\":%s,\"dsr\":%s,\"dcd\":%s,\"ri\":%s,"
	        "\"raw_status\":%d,\"rts\":%s,\"dtr\":%s,\"break\":%s}\n",
	        (status & SERIAL_CTS) ? "true" : "false",
	        (status & SERIAL_DSR) ? "true" : "false",
	        (status & SERIAL_CD) ? "true" : "false",
	        (status & SERIAL_RI) ? "true" : "false",
	        status,
	        trace_rts ? "true" : "false",
	        trace_dtr ? "true" : "false",
	        trace_break ? "true" : "false");
	fflush(arltrace_fp);
}

void CDirectSerial::traceControlLines(const char *event)
{
	if (!arltrace_fp) return;

	traceCommonFields(event);
	fprintf(arltrace_fp,
	        ",\"rts\":%s,\"dtr\":%s,\"cts\":%s,\"dsr\":%s,"
	        "\"dcd\":%s,\"ri\":%s,\"break\":%s}\n",
	        trace_rts ? "true" : "false",
	        trace_dtr ? "true" : "false",
	        getCTS() ? "true" : "false",
	        getDSR() ? "true" : "false",
	        getCD() ? "true" : "false",
	        getRI() ? "true" : "false",
	        trace_break ? "true" : "false");
	fflush(arltrace_fp);
}

CDirectSerial::CDirectSerial (Bitu id, CommandLine* cmd)
					:CSerial (id, cmd) {
	InstallationSuccessful = false;
	comport = nullptr;

	rx_retry = 0;
    rx_retry_max = 0;
    rx_state = 0;

	std::string tmpstring;
	if(!cmd->FindStringBegin("realport:",tmpstring,false)) return;
	realport_name = tmpstring;

	LOG_MSG ("Serial%d: Opening %s", (int)(COMNUMBER), tmpstring.c_str());
	if(!SERIAL_open(tmpstring.c_str(), &comport)) {
		char errorbuffer[256];
		SERIAL_getErrorString(errorbuffer, sizeof(errorbuffer));
		LOG_MSG("Serial%d: Serial Port \"%s\" could not be opened.",
			(int)(COMNUMBER), tmpstring.c_str());
		LOG_MSG("%s",errorbuffer);
		return;
	}

	std::string trace_path;
	if (cmd->FindStringBegin("arltrace:", trace_path, false)) {
		traceOpen(trace_path);
	}

	// rxdelay: How many milliseconds to wait before causing an
	// overflow when the application is unresponsive.
	if(getBituSubstring("rxdelay:", &rx_retry_max, cmd)) {
		if(!(rx_retry_max<=10000)) {
			rx_retry_max=0;
		}
	}

	CSerial::Init_Registers();
	InstallationSuccessful = true;
	rx_state = D_RX_IDLE;
	traceMessage("open", "directserial opened");
	setEvent(SERIAL_POLLING_EVENT, 1); // millisecond receive tick
}

CDirectSerial::~CDirectSerial () {
	traceMessage("close", "directserial closing");
	if(arltrace_fp) {
		fclose(arltrace_fp);
		arltrace_fp = nullptr;
	}
	if(comport) SERIAL_close(comport);
	// We do not use own events so we don't have to clear them.
}

// CanReceive: true:UART part has room left
// doReceive:  true:there was really a byte to receive
// rx_retry is incremented in polling events

// in POLLING_EVENT: always add new polling event
// D_RX_IDLE + CanReceive + doReceive		-> D_RX_WAIT   , add RX_EVENT
// D_RX_IDLE + CanReceive + not doReceive	-> D_RX_IDLE
// D_RX_IDLE + not CanReceive				-> D_RX_BLOCKED, add RX_EVENT

// D_RX_BLOCKED + CanReceive + doReceive	-> D_RX_FASTWAIT, rem RX_EVENT
//											   rx_retry=0   , add RX_EVENT
// D_RX_BLOCKED + CanReceive + !doReceive	-> D_RX_IDLE,     rem RX_EVENT
//											   rx_retry=0
// D_RX_BLOCKED + !CanReceive + doReceive + retry < max	-> D_RX_BLOCKED, rx_retry++ 
// D_RX_BLOCKED + !CanReceive + doReceive + retry >=max	-> rx_retry=0 	

// to be continued...

void CDirectSerial::handleUpperEvent(uint16_t type) {
/*
#if SERIAL_DEBUG
		const char* s;
		const char* s2;
		switch(type) {
		case SERIAL_POLLING_EVENT: s = "POLLING_EVENT"; break;
		case SERIAL_RX_EVENT: s = "RX_EVENT"; break;
		case SERIAL_TX_EVENT: s = "TX_EVENT"; break;
		case SERIAL_THR_EVENT: s = "THR_EVENT"; break;
		}
		switch(rx_state) {
		case D_RX_IDLE: s2 = "RX_IDLE"; break;
		case D_RX_WAIT: s2 = "RX_WAIT"; break;
		case D_RX_BLOCKED: s2 = "RX_BLOCKED"; break;
		case D_RX_FASTWAIT: s2 = "RX_FASTWAIT"; break;
		}
		log_ser(dbg_aux,"Directserial: Event enter %s, %s",s,s2);
#endif
		*/

	switch(type) {
		case SERIAL_POLLING_EVENT: {
			setEvent(SERIAL_POLLING_EVENT, 1.0f);
			// update Modem input line states
			switch(rx_state) {
				case D_RX_IDLE:
					if(CanReceiveByte()) {
						if(doReceive()) {
							// a byte was received
							rx_state=D_RX_WAIT;
							setEvent(SERIAL_RX_EVENT, bytetime*0.9f);
						} // else still idle
					} else {
#if SERIAL_DEBUG
						if(!dbgmsg_poll_block) {
							log_ser(dbg_aux,"Directserial: block on polling.");
							dbgmsg_poll_block=true;
						}
#endif
						rx_state=D_RX_BLOCKED;
						// have both delays (1ms + bytetime)
						setEvent(SERIAL_RX_EVENT, bytetime*0.9f);
					}
					break;
				case D_RX_BLOCKED:
                    // one timeout tick
					if(!CanReceiveByte()) {
						rx_retry++;
						if(rx_retry>=rx_retry_max) {
							// it has timed out:
							rx_retry=0;
							removeEvent(SERIAL_RX_EVENT);
							if(doReceive()) {
								// read away everything
								// this will set overrun errors
								while(doReceive());
								rx_state=D_RX_WAIT;
								setEvent(SERIAL_RX_EVENT, bytetime*0.9f);
							} else {
								// much trouble about nothing
                                rx_state=D_RX_IDLE;
							}
						} // else wait further
					} else {
						// good: we can receive again
#if SERIAL_DEBUG
						dbgmsg_poll_block=false;
						dbgmsg_rx_block=false;
#endif
						removeEvent(SERIAL_RX_EVENT);
						rx_retry=0;
						if(doReceive()) {
							rx_state=D_RX_FASTWAIT;
							setEvent(SERIAL_RX_EVENT, bytetime*0.65f);
						} else {
							// much trouble about nothing
							rx_state=D_RX_IDLE;
						}
					}
					break;

				case D_RX_WAIT:
				case D_RX_FASTWAIT:
					break;
			}
			updateMSR();
			break;
		}
		case SERIAL_RX_EVENT: {
			switch(rx_state) {
				case D_RX_IDLE:
					LOG_MSG("internal error in directserial");
					break;

				case D_RX_BLOCKED: // try to receive
				case D_RX_WAIT:
				case D_RX_FASTWAIT:
					if(CanReceiveByte()) {
						// just works or unblocked
						rx_retry=0; // not waiting anymore
						if(doReceive()) {
							if(rx_state==D_RX_WAIT) setEvent(SERIAL_RX_EVENT, bytetime*0.9f);
							else {
								// maybe unblocked
								rx_state=D_RX_FASTWAIT;
								setEvent(SERIAL_RX_EVENT, bytetime*0.65f);
							}
						} else {
							// didn't receive anything
							rx_state=D_RX_IDLE;
						}
					} else {
						// blocking now or still blocked
#if SERIAL_DEBUG
						if(rx_state==D_RX_BLOCKED) {
							if(!dbgmsg_rx_block) {
                                log_ser(dbg_aux,"Directserial: rx still blocked (retry=%d)",rx_retry);
								dbgmsg_rx_block=true;
							}
						}






						else log_ser(dbg_aux,"Directserial: block on continued rx (retry=%d).",rx_retry);
#endif
						setEvent(SERIAL_RX_EVENT, bytetime*0.65f);
						rx_state=D_RX_BLOCKED;
					}

					break;
			}
			updateMSR();
			break;
		}
		case SERIAL_TX_EVENT: {
			// Maybe echo circuit works a bit better this way
			if(rx_state==D_RX_IDLE && CanReceiveByte()) {
				if(doReceive()) {
					// a byte was received
					rx_state=D_RX_WAIT;
					setEvent(SERIAL_RX_EVENT, bytetime*0.9f);
				}
			}
			ByteTransmitted();
			updateMSR();
			break;
		}
		case SERIAL_THR_EVENT: {
			ByteTransmitting();
			setEvent(SERIAL_TX_EVENT,bytetime*1.1f);
			break;				   
		}
	}
	/*
	#if SERIAL_DEBUG
		switch(type) {
		case SERIAL_POLLING_EVENT: s = "POLLING_EVENT"; break;
		case SERIAL_RX_EVENT: s = "RX_EVENT"; break;
		case SERIAL_TX_EVENT: s = "TX_EVENT"; break;
		case SERIAL_THR_EVENT: s = "THR_EVENT"; break;
		}
		switch(rx_state) {
			case D_RX_IDLE: s2 = "RX_IDLE"; break;
			case D_RX_WAIT: s2 = "RX_WAIT"; break;
			case D_RX_BLOCKED: s2 = "RX_BLOCKED"; break;
			case D_RX_FASTWAIT: s2 = "RX_FASTWAIT"; break;
		}
		log_ser(dbg_aux,"Directserial: Event exit %s, %s",s,s2);
#endif*/
}

bool CDirectSerial::doReceive() {
	int value = SERIAL_getextchar(comport);
	if(value) {
		const uint8_t data = (uint8_t)(value&0xff);
		const uint8_t error = (uint8_t)((value&0xff00)>>8);
		traceByte("rx", data, error);
		receiveByteEx(data,error);
		return true;
	}
	return false;
}

// updatePortConfig is called when emulated app changes the serial port
// parameters baudrate, stopbits, number of databits, parity.
void CDirectSerial::updatePortConfig (uint16_t divider, uint8_t lcr) {
	uint8_t parity = 0;

	switch ((lcr & 0x38)>>3) {
	case 0x1: parity='o'; break;
	case 0x3: parity='e'; break;
	case 0x5: parity='m'; break;
	case 0x7: parity='s'; break;
	default: parity='n'; break;
	}

	uint8_t bytelength = (lcr & 0x3)+5;

	// baudrate
	Bitu baudrate;
	if(divider==0) baudrate=115200u;
	else baudrate = 115200u / divider;

	// stopbits
	uint8_t stopbits;
	if (lcr & 0x4) {
		if (bytelength == 5) stopbits = SERIAL_15STOP;
		else stopbits = SERIAL_2STOP;
	} else stopbits = SERIAL_1STOP;

	const bool accepted = SERIAL_setCommParameters(comport, (int)baudrate, (char)parity, (char)stopbits, (char)bytelength);
	traceConfig((int)baudrate, (char)parity, stopbits, bytelength, accepted);
	if(!accepted) {
#if SERIAL_DEBUG
		log_ser(dbg_aux,"Serial port settings not supported by host." );
#endif
		LOG_MSG ("Serial%d: Desired serial mode not supported (%d,%d,%c,%d)",
			(int)(COMNUMBER),(int)baudrate,(int)bytelength,parity,(int)stopbits);
	} 
	CDirectSerial::setRTSDTR(getRTS(), getDTR());
}

void CDirectSerial::updateMSR () {
	int new_status = SERIAL_getmodemstatus(comport);
	traceModemStatus(new_status);

	setCTS((new_status&SERIAL_CTS)? true:false);
	setDSR((new_status&SERIAL_DSR)? true:false);
	setRI((new_status&SERIAL_RI)? true:false);
	setCD((new_status&SERIAL_CD)? true:false);
}

void CDirectSerial::transmitByte (uint8_t val, bool first) {
	traceByte("tx", val, 0);
	if(!SERIAL_sendchar(comport, (char)val)) {
		traceMessage("tx_error", "COM port write failed");
		LOG_MSG("Serial%d: COM port error: write failed!", (int)COMNUMBER);
	}
	if(first) setEvent(SERIAL_THR_EVENT, bytetime/8);
	else setEvent(SERIAL_TX_EVENT, bytetime);
}


// setBreak(val) switches break on or off
void CDirectSerial::setBreak (bool value) {
	trace_break = value;
	SERIAL_setBREAK(comport,value);
	traceControlLines("break");
}

// updateModemControlLines(mcr) sets DTR and RTS. 
void CDirectSerial::setRTSDTR(bool rts, bool dtr) {
	trace_rts = rts;
	trace_dtr = dtr;
	SERIAL_setRTS(comport,rts);
	SERIAL_setDTR(comport,dtr);
	traceControlLines("control");
}

void CDirectSerial::setRTS(bool val) {
	trace_rts = val;
	SERIAL_setRTS(comport,val);
	traceControlLines("control");
}

void CDirectSerial::setDTR(bool val) {
	trace_dtr = val;
	SERIAL_setDTR(comport,val);
	traceControlLines("control");
}

#endif
