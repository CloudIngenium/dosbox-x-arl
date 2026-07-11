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
#include <cstdio>
#include <cctype>

/* This is a serial passthrough class.  Its amazingly simple to */
/* write now that the serial ports themselves were abstracted out */

void CDirectSerial::traceOpen(const std::string &path)
{
	arltrace_path = path;
	traceOpenCurrentPath();
}

bool CDirectSerial::traceOpenCurrentPath()
{
	arltrace_start_tick = GetTicks();
	arltrace_last_io_tick = arltrace_start_tick;
	arltrace_last_hang_tick = arltrace_start_tick;
	arltrace_limit_reached = false;
	arltrace_fp = fopen(arltrace_path.c_str(), "ab");
	if (!arltrace_fp) {
		LOG_MSG("Serial%d: ARL trace file \"%s\" could not be opened.",
		        (int)COMNUMBER, arltrace_path.c_str());
		return false;
	}

	traceMessage("trace_open", "ARL directserial trace enabled");
	return true;
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
	        "\"guest_com\":\"COM%d\",\"serial\":%d,\"session\":",
	        epoch_ms, (unsigned int)elapsed_ms, (double)PIC_FullIndex(),
	        (int)COMNUMBER, (int)COMNUMBER);
	traceJsonString(arltrace_session.empty() ? "default" : arltrace_session.c_str());
	fputs(",\"level\":", arltrace_fp);
	traceJsonString(traceLevelName());
	fputs(",\"realport\":", arltrace_fp);
	traceJsonString(realport_name.c_str());
	fputs(",\"event\":", arltrace_fp);
	traceJsonString(event);
}

void CDirectSerial::traceFlush()
{
	if (!arltrace_fp) return;
	fflush(arltrace_fp);
	traceCheckLimit();
}

void CDirectSerial::traceCheckLimit()
{
	if (!arltrace_fp || !arltrace_max_bytes || arltrace_limit_reached) return;

	const long offset = ftell(arltrace_fp);
	if (offset < 0 || (unsigned long long)offset < arltrace_max_bytes) return;

	arltrace_limit_reached = true;
	traceCommonFields("trace_limit");
	fprintf(arltrace_fp,
	        ",\"message\":\"ARL trace size limit reached; closing trace\","
	        "\"current_bytes\":%ld,\"max_bytes\":%llu}\n",
	        offset, arltrace_max_bytes);
	fflush(arltrace_fp);
	fclose(arltrace_fp);
	arltrace_fp = nullptr;
	trace_last_error = "trace_limit";
	LOG_MSG("Serial%d: ARL trace size limit reached; trace file closed.",
	        (int)COMNUMBER);
}

void CDirectSerial::traceMessage(const char *event, const char *message)
{
	if (!arltrace_fp) return;

	traceCommonFields(event);
	fputs(",\"message\":", arltrace_fp);
	traceJsonString(message);
	fputs("}\n", arltrace_fp);
	traceFlush();
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
	arltrace_last_io_tick = GetTicks();
	if (!strcmp(event, "tx")) {
		trace_have_tx = true;
		trace_last_tx = val;
		trace_tx_count++;
	} else if (!strcmp(event, "rx")) {
		trace_have_rx = true;
		trace_last_rx = val;
		trace_last_rx_error = error;
		trace_rx_count++;
		if (error) trace_last_error = "rx_error";
	}

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
	traceFlush();
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
	traceFlush();
	traceHostState("host_config");
}

void CDirectSerial::traceModemStatus(int status)
{
	if (status == trace_modem_status) return;
	trace_modem_status = status;

	if (!arltrace_fp) return;

	const bool raw_cts = (status & SERIAL_CTS) ? true : false;
	const bool raw_dsr = (status & SERIAL_DSR) ? true : false;
	const bool raw_dcd = (status & SERIAL_CD) ? true : false;
	const bool raw_ri = (status & SERIAL_RI) ? true : false;
	const bool guest_cts = raw_cts || arl_force_cts;
	const bool guest_dsr = raw_dsr || arl_force_dsr;
	const bool guest_dcd = raw_dcd || arl_force_dcd;

	traceCommonFields("modem");
	fprintf(arltrace_fp,
	        ",\"cts\":%s,\"dsr\":%s,\"dcd\":%s,\"ri\":%s,"
	        "\"raw_cts\":%s,\"raw_dsr\":%s,\"raw_dcd\":%s,\"raw_ri\":%s,"
	        "\"forced_cts\":%s,\"forced_dsr\":%s,\"forced_dcd\":%s,"
	        "\"raw_status\":%d,\"rts\":%s,\"dtr\":%s,\"break\":%s}\n",
	        guest_cts ? "true" : "false",
	        guest_dsr ? "true" : "false",
	        guest_dcd ? "true" : "false",
	        raw_ri ? "true" : "false",
	        raw_cts ? "true" : "false",
	        raw_dsr ? "true" : "false",
	        raw_dcd ? "true" : "false",
	        raw_ri ? "true" : "false",
	        arl_force_cts ? "true" : "false",
	        arl_force_dsr ? "true" : "false",
	        arl_force_dcd ? "true" : "false",
	        status,
	        trace_rts ? "true" : "false",
	        trace_dtr ? "true" : "false",
	        trace_break ? "true" : "false");
	traceFlush();
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
	traceFlush();
}

void CDirectSerial::traceSnapshot(const char *event, const SerialTraceSnapshot &snapshot)
{
	if (!arltrace_fp) return;

	traceCommonFields(event);
	fprintf(arltrace_fp,
	        ",\"rx_state\":%u,\"rx_retry\":%u,\"rx_retry_max\":%u,"
	        "\"rx_fifo_usage\":%u,\"tx_fifo_usage\":%u,"
	        "\"rx_fifo_free\":%u,\"tx_fifo_free\":%u,"
	        "\"errors_in_fifo\":%u,\"rx_interrupt_threshold\":%u,"
	        "\"framing_errors\":%u,\"parity_errors\":%u,"
	        "\"overrun_errors\":%u,\"tx_overrun_errors\":%u,"
	        "\"overrun_if0\":%u,\"break_errors\":%u,"
	        "\"ier\":%u,\"isr\":%u,\"lcr\":%u,\"lsr\":%u,"
	        "\"fcr\":%u,\"waiting_interrupts\":%u,"
	        "\"irq_active\":%s,\"loopback\":%s,"
	        "\"tx_count\":%u,\"rx_count\":%u,\"tx_errors\":%u}\n",
	        (unsigned int)rx_state, (unsigned int)rx_retry, (unsigned int)rx_retry_max,
	        (unsigned int)snapshot.rx_fifo_usage, (unsigned int)snapshot.tx_fifo_usage,
	        (unsigned int)snapshot.rx_fifo_free, (unsigned int)snapshot.tx_fifo_free,
	        (unsigned int)snapshot.errors_in_fifo, (unsigned int)snapshot.rx_interrupt_threshold,
	        (unsigned int)snapshot.framing_errors, (unsigned int)snapshot.parity_errors,
	        (unsigned int)snapshot.overrun_errors, (unsigned int)snapshot.tx_overrun_errors,
	        (unsigned int)snapshot.overrun_if0, (unsigned int)snapshot.break_errors,
	        (unsigned int)snapshot.ier, (unsigned int)snapshot.isr,
	        (unsigned int)snapshot.lcr, (unsigned int)snapshot.lsr,
	        (unsigned int)snapshot.fcr, (unsigned int)snapshot.waiting_interrupts,
	        snapshot.irq_active ? "true" : "false",
	        snapshot.loopback ? "true" : "false",
	        (unsigned int)trace_tx_count, (unsigned int)trace_rx_count,
	        (unsigned int)trace_tx_errors);
	traceFlush();
}

void CDirectSerial::traceHostState(const char *event)
{
	if (!arltrace_fp || arltrace_level != ARL_TRACE_FULL || !comport) return;

	SERIAL_host_state state;
	if (!SERIAL_getHostState(comport, &state)) {
		traceMessage(event, "host serial state unavailable");
		return;
	}

	traceCommonFields(event);
	fprintf(arltrace_fp,
	        ",\"host_available\":%s,\"host_baud\":%d,"
	        "\"host_data_bits\":%d,\"host_parity\":\"%c\","
	        "\"host_stop_bits\":%d,\"host_out_cts_flow\":%s,"
	        "\"host_out_dsr_flow\":%s,\"host_dsr_sensitivity\":%s,"
	        "\"host_out_x\":%s,\"host_in_x\":%s,"
	        "\"host_abort_on_error\":%s,\"host_dtr_control\":%d,"
	        "\"host_rts_control\":%d,\"host_read_interval_timeout\":%lu,"
	        "\"host_read_total_timeout_multiplier\":%lu,"
	        "\"host_read_total_timeout_constant\":%lu,"
	        "\"host_write_total_timeout_multiplier\":%lu,"
	        "\"host_write_total_timeout_constant\":%lu,"
	        "\"host_modem_status\":%d}\n",
	        state.available ? "true" : "false", state.baudrate,
	        state.length, state.parity ? state.parity : 'n',
	        state.stopbits,
	        state.out_cts_flow ? "true" : "false",
	        state.out_dsr_flow ? "true" : "false",
	        state.dsr_sensitivity ? "true" : "false",
	        state.out_x ? "true" : "false",
	        state.in_x ? "true" : "false",
	        state.abort_on_error ? "true" : "false",
	        state.dtr_control, state.rts_control,
	        state.read_interval_timeout,
	        state.read_total_timeout_multiplier,
	        state.read_total_timeout_constant,
	        state.write_total_timeout_multiplier,
	        state.write_total_timeout_constant,
	        state.modem_status);
	traceFlush();
}

void CDirectSerial::traceHangSnapshot()
{
	if (!arltrace_fp || !arltrace_hang_ms) return;

	const uint32_t now = GetTicks();
	if ((now - arltrace_last_io_tick) < arltrace_hang_ms) return;
	if ((now - arltrace_last_hang_tick) < arltrace_hang_ms) return;

	arltrace_last_hang_tick = now;
	traceSnapshot("hang_snapshot", getTraceSnapshot());
	traceHostState("host_hang_snapshot");
}

std::string CDirectSerial::traceRotatePath() const
{
	if (arltrace_path.empty()) return "";

	char stamp[32];
	time_t now = time(nullptr);
	struct tm *local = localtime(&now);
	if (local) strftime(stamp, sizeof(stamp), "%Y%m%d-%H%M%S", local);
	else snprintf(stamp, sizeof(stamp), "%ld", (long)now);

	const size_t slash = arltrace_path.find_last_of("\\/");
	const size_t dot = arltrace_path.find_last_of('.');
	if (dot != std::string::npos && (slash == std::string::npos || dot > slash)) {
		return arltrace_path.substr(0, dot) + "-" + stamp + arltrace_path.substr(dot);
	}
	return arltrace_path + "-" + stamp + ".ndjson";
}

const char *CDirectSerial::traceLevelName() const
{
	switch (arltrace_level) {
	case ARL_TRACE_FULL: return "full";
	case ARL_TRACE_UART: return "uart";
	case ARL_TRACE_UARTDATA: return "uartdata";
	default: return "basic";
	}
}

bool CDirectSerial::arlTraceIsEnabled() const
{
	return arltrace_fp != nullptr;
}

std::string CDirectSerial::arlTraceStatus()
{
	char buffer[1536];
	snprintf(buffer, sizeof(buffer),
	         "COM%d ARL trace: %s\n"
	         "  path: %s\n"
	         "  session: %s\n"
	         "  level: %s\n"
	         "  realport: %s\n"
	         "  tx_count: %u last_tx: %s%02X\n"
	         "  rx_count: %u last_rx: %s%02X error: %u\n"
	         "  lines: RTS=%d DTR=%d CTS=%d DSR=%d DCD=%d RI=%d BREAK=%d\n"
	         "  line_options: forceCTS=%d forceDSR=%d forceDCD=%d holdRTS=%d holdDTR=%d\n"
	         "  rx_state=%u rx_retry=%u rx_retry_max=%u hang_ms=%u\n"
	         "  last_error: %s\n",
	         (int)COMNUMBER,
	         arltrace_fp ? "open" : "closed",
	         arltrace_path.empty() ? "(none)" : arltrace_path.c_str(),
	         arltrace_session.empty() ? "default" : arltrace_session.c_str(),
	         traceLevelName(),
	         realport_name.empty() ? "(unknown)" : realport_name.c_str(),
	         (unsigned int)trace_tx_count,
	         trace_have_tx ? "0x" : "",
	         trace_have_tx ? (unsigned int)trace_last_tx : 0,
	         (unsigned int)trace_rx_count,
	         trace_have_rx ? "0x" : "",
	         trace_have_rx ? (unsigned int)trace_last_rx : 0,
	         (unsigned int)trace_last_rx_error,
	         trace_rts ? 1 : 0,
	         trace_dtr ? 1 : 0,
	         getCTS() ? 1 : 0,
	         getDSR() ? 1 : 0,
	         getCD() ? 1 : 0,
	         getRI() ? 1 : 0,
	         trace_break ? 1 : 0,
	         arl_force_cts ? 1 : 0,
	         arl_force_dsr ? 1 : 0,
	         arl_force_dcd ? 1 : 0,
	         arl_hold_rts ? 1 : 0,
	         arl_hold_dtr ? 1 : 0,
	         (unsigned int)rx_state,
	         (unsigned int)rx_retry,
	         (unsigned int)rx_retry_max,
	         (unsigned int)arltrace_hang_ms,
	         trace_last_error.empty() ? "(none)" : trace_last_error.c_str());
	return std::string(buffer);
}

void CDirectSerial::arlTraceMark(const char *message)
{
	traceMessage("mark", message ? message : "");
}

bool CDirectSerial::arlTraceRotate()
{
	if (arltrace_path.empty()) return false;
	if (arltrace_fp) {
		traceMessage("rotate", "closing current trace file");
		fclose(arltrace_fp);
		arltrace_fp = nullptr;
	}
	arltrace_path = traceRotatePath();
	const bool opened = traceOpenCurrentPath();
	if (opened) traceMessage("rotate", "opened rotated trace file");
	return opened;
}

void CDirectSerial::arlTraceUartEvent(const char *direction, const char *reg,
                                      Bitu port, uint8_t value,
                                      const SerialTraceSnapshot &snapshot)
{
	if (!arltrace_fp || arltrace_level < ARL_TRACE_UARTDATA) return;

	const bool is_data_register =
	        (direction && reg &&
	         ((strcmp(direction, "uart_read") == 0 && strcmp(reg, "RHR") == 0) ||
	          (strcmp(direction, "uart_write") == 0 && strcmp(reg, "THR") == 0)));
	if (arltrace_level == ARL_TRACE_UARTDATA && !is_data_register) return;

	traceCommonFields(direction);
	fprintf(arltrace_fp,
	        ",\"register\":");
	traceJsonString(reg ? reg : "");
	fprintf(arltrace_fp,
	        ",\"io_port\":%u,\"value_dec\":%u,\"value_hex\":\"%02X\","
	        "\"rx_state\":%u,\"rx_retry\":%u,\"rx_retry_max\":%u,"
	        "\"rx_fifo_usage\":%u,\"tx_fifo_usage\":%u,"
	        "\"rx_fifo_free\":%u,\"tx_fifo_free\":%u,"
	        "\"errors_in_fifo\":%u,\"framing_errors\":%u,"
	        "\"parity_errors\":%u,\"overrun_errors\":%u,"
	        "\"tx_overrun_errors\":%u,\"break_errors\":%u,"
	        "\"ier\":%u,\"isr\":%u,\"lcr\":%u,\"lsr\":%u,"
	        "\"fcr\":%u,\"waiting_interrupts\":%u,"
	        "\"irq_active\":%s,\"loopback\":%s}\n",
	        (unsigned int)port, (unsigned int)value, (unsigned int)value,
	        (unsigned int)rx_state, (unsigned int)rx_retry, (unsigned int)rx_retry_max,
	        (unsigned int)snapshot.rx_fifo_usage, (unsigned int)snapshot.tx_fifo_usage,
	        (unsigned int)snapshot.rx_fifo_free, (unsigned int)snapshot.tx_fifo_free,
	        (unsigned int)snapshot.errors_in_fifo,
	        (unsigned int)snapshot.framing_errors,
	        (unsigned int)snapshot.parity_errors,
	        (unsigned int)snapshot.overrun_errors,
	        (unsigned int)snapshot.tx_overrun_errors,
	        (unsigned int)snapshot.break_errors,
	        (unsigned int)snapshot.ier, (unsigned int)snapshot.isr,
	        (unsigned int)snapshot.lcr, (unsigned int)snapshot.lsr,
	        (unsigned int)snapshot.fcr, (unsigned int)snapshot.waiting_interrupts,
	        snapshot.irq_active ? "true" : "false",
	        snapshot.loopback ? "true" : "false");
	traceFlush();
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
	if (cmd->FindStringBegin("arltracesession:", arltrace_session, false) &&
	    arltrace_session.empty()) {
		arltrace_session = "default";
	}
	std::string trace_level;
	if (cmd->FindStringBegin("arltracelevel:", trace_level, false)) {
		for (auto &ch : trace_level)
			ch = (char)tolower((unsigned char)ch);
		if (trace_level == "full") arltrace_level = ARL_TRACE_FULL;
		else if (trace_level == "uart") arltrace_level = ARL_TRACE_UART;
		else if (trace_level == "uartdata") arltrace_level = ARL_TRACE_UARTDATA;
		else arltrace_level = ARL_TRACE_BASIC;
	}
	Bitu line_option = 0;
	if (getBituSubstring("arlforcects:", &line_option, cmd))
		arl_force_cts = line_option != 0;
	line_option = 0;
	if (getBituSubstring("arlforcedsr:", &line_option, cmd))
		arl_force_dsr = line_option != 0;
	line_option = 0;
	if (getBituSubstring("arlforcedcd:", &line_option, cmd))
		arl_force_dcd = line_option != 0;
	line_option = 0;
	if (getBituSubstring("arlholdrts:", &line_option, cmd))
		arl_hold_rts = line_option != 0;
	line_option = 0;
	if (getBituSubstring("arlholddtr:", &line_option, cmd))
		arl_hold_dtr = line_option != 0;
	line_option = 0;
	if (getBituSubstring("arlresultobserve:", &line_option, cmd))
		arl_result_observe = line_option != 0;
	line_option = 0;
	if (getBituSubstring("arlresultretrylow:", &line_option, cmd)) {
		arl_result_retry_low = line_option != 0;
		if (arl_result_retry_low) arl_result_observe = true;
	}
	getBituSubstring("arltracehangms:", &arltrace_hang_ms, cmd);
	if (arltrace_hang_ms > 3600000) arltrace_hang_ms = 3600000;
	Bitu arltrace_max_mb = 0;
	getBituSubstring("arltracemaxmb:", &arltrace_max_mb, cmd);
	if (arltrace_max_mb > 4096) arltrace_max_mb = 4096;
	arltrace_max_bytes = (unsigned long long)arltrace_max_mb * 1024ULL * 1024ULL;

	if (cmd->FindStringBegin("arltrace:", trace_path, false)) {
		traceOpen(trace_path);
	}
	if (arl_force_cts || arl_force_dsr || arl_force_dcd ||
	    arl_hold_rts || arl_hold_dtr) {
		traceMessage("line_options", "ARL modem-line compatibility options active");
		LOG_MSG("Serial%d: ARL modem-line options: force CTS=%d DSR=%d DCD=%d, hold RTS=%d DTR=%d",
		        (int)COMNUMBER,
		        arl_force_cts ? 1 : 0,
		        arl_force_dsr ? 1 : 0,
		        arl_force_dcd ? 1 : 0,
		        arl_hold_rts ? 1 : 0,
		        arl_hold_dtr ? 1 : 0);
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
	traceHostState("host_open");
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
	traceHangSnapshot();
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
	if (!arl_retry_guest_bytes.empty()) {
		const uint8_t data = arl_retry_guest_bytes.front();
		arl_retry_guest_bytes.pop_front();
		traceByte("rx_presented", data, 0);
		observeRxByte(data);
		receiveByteEx(data, 0);
		return true;
	}

	int value = SERIAL_getextchar(comport);
	if(value) {
		const uint8_t data = (uint8_t)(value&0xff);
		const uint8_t error = (uint8_t)((value&0xff00)>>8);
		traceByte("rx", data, error);
		if (arl_result_retry_low && arl_retry_blocked)
			return false;
		if (arl_result_retry_low && arl_retry_correction_pending) {
			if (arl_retry_host_frame.size() >= 2048) {
				traceMessage("result_correction_overflow", "retry frame exceeded 2048 bytes");
				arl_retry_host_frame.clear();
				arl_retry_correction_pending = false;
				receiveByteEx(data, error);
				return true;
			}
			arl_retry_host_frame.push_back((char)data);
			if (data != '\r') return false;

			std::string presented;
			int target_checksum = -1;
			const int original_checksum = arl_physical_result_checksum;
			if (!buildEquivalentResult(arl_retry_host_frame, presented, target_checksum)) {
				presented = arl_retry_host_frame;
				traceResultCorrection(arl_retry_host_frame, presented,
				                      original_checksum, original_checksum,
				                      "no_safe_equivalent");
			} else {
				arl_current_result_mutated = true;
				arl_last_result_mutated = true;
				traceResultCorrection(arl_retry_host_frame, presented,
				                      original_checksum, target_checksum,
				                      "reactive_retry_after_question");
			}
			for (const unsigned char ch : presented)
				arl_retry_guest_bytes.push_back(ch);
			arl_retry_host_frame.clear();
			arl_retry_correction_pending = false;
			if (arl_retry_guest_bytes.empty()) return false;
			const uint8_t first = arl_retry_guest_bytes.front();
			arl_retry_guest_bytes.pop_front();
			traceByte("rx_presented", first, 0);
			observeRxByte(first);
			receiveByteEx(first, 0);
			return true;
		}
		observeRxByte(data);
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

	setCTS(((new_status&SERIAL_CTS) || arl_force_cts) ? true:false);
	setDSR(((new_status&SERIAL_DSR) || arl_force_dsr) ? true:false);
	setRI((new_status&SERIAL_RI)? true:false);
	setCD(((new_status&SERIAL_CD) || arl_force_dcd) ? true:false);
}

void CDirectSerial::transmitByte (uint8_t val, bool first) {
	traceByte("tx", val, 0);
	observeTxByte(val);
	if(!SERIAL_sendchar(comport, (char)val)) {
		trace_tx_errors++;
		trace_last_error = "tx_error";
		traceMessage("tx_error", "COM port write failed");
		LOG_MSG("Serial%d: COM port error: write failed!", (int)COMNUMBER);
	}
	if(first) setEvent(SERIAL_THR_EVENT, bytetime/8);
	else setEvent(SERIAL_TX_EVENT, bytetime);
}

void CDirectSerial::observeTxByte(uint8_t val) {
	if (!arl_result_observe) return;
	// IMPACT 2.4-B1 sends a rejection as a lone '?' byte. Some protocol
	// fixtures include a trailing CR, so accept both forms while a result is
	// pending and clear the TX accumulator before the next command.
	if (val == '?' && arl_awaiting_result && arl_tx_frame.empty()) {
		traceObservedDecision("rejected");
		handleRejectedResult();
		arl_tx_frame.clear();
		return;
	}
	if (arl_tx_frame.size() >= 1024) arl_tx_frame.clear();
	arl_tx_frame.push_back((char)val);
	if (val != '\r') return;

	if (arl_tx_frame.compare(0, 4, "#rd ") == 0) {
		arl_awaiting_result = true;
		arl_rx_frame.clear();
		arl_retry_host_frame.clear();
		arl_retry_guest_bytes.clear();
		arl_retry_correction_pending = false;
		arl_retry_blocked = false;
		arl_current_result_mutated = false;
		arl_last_result_mutated = false;
		arl_result_corrector.reset();
		arl_last_claimed_checksum = -1;
		arl_last_computed_checksum = -1;
		arl_physical_result_checksum = -1;
		traceMessage("result_observe_armed", "IMPACT requested an analysis result");
	} else if (arl_tx_frame.compare(0, 4, "#em ") == 0) {
		traceObservedDecision("accepted");
		arl_awaiting_result = false;
	} else if (arl_tx_frame == "?\r") {
		traceObservedDecision("rejected");
		handleRejectedResult();
	}
	arl_tx_frame.clear();
}

void CDirectSerial::handleRejectedResult() {
	if (arl_result_retry_low && !arl_result_corrector.exhausted()) {
		arl_awaiting_result = true;
		arl_retry_correction_pending = true;
		arl_retry_host_frame.clear();
		arl_rx_frame.clear();
		arl_current_result_mutated = false;
		traceMessage("result_correction_armed", "IMPACT rejected result; waiting for repeated row");
		return;
	}

	arl_awaiting_result = false;
	if (arl_result_retry_low && arl_result_corrector.exhausted()) {
		arl_retry_blocked = true;
		traceMessage("result_correction_exhausted",
		             "all safe checksum targets were rejected; inbound retries are blocked");
	}
}

void CDirectSerial::observeRxByte(uint8_t val) {
	if (!arl_result_observe || !arl_awaiting_result) return;
	if (arl_rx_frame.size() >= 2048) {
		traceMessage("result_observe_overflow", "result frame exceeded 2048 bytes");
		arl_rx_frame.clear();
		arl_awaiting_result = false;
		return;
	}
	arl_rx_frame.push_back((char)val);
	if (val != '\r') return;
	traceObservedResult(arl_rx_frame);
	arl_rx_frame.clear();
}

void CDirectSerial::traceObservedResult(const std::string &frame) {
	if (!arltrace_fp) return;
	const size_t end = frame.empty() ? 0 : frame.size() - 1;
	const size_t separator = frame.rfind(' ', end);
	int claimed = -1;
	int computed = -1;
	bool valid = false;
	if (frame.size() >= 4 && separator != std::string::npos && separator + 1 < end) {
		claimed = 0;
		bool digits = true;
		for (size_t i = separator + 1; i < end; ++i) {
			if (frame[i] < '0' || frame[i] > '9') { digits = false; break; }
			claimed = claimed * 10 + (frame[i] - '0');
		}
		if (digits) {
			computed = 0;
			const size_t content_start = frame[0] == '#' ? 1 : 0;
			for (size_t i = content_start; i <= separator; ++i)
				computed = (computed + (unsigned char)frame[i]) & 0xff;
			valid = claimed == computed;
		} else claimed = -1;
	}
	arl_last_claimed_checksum = claimed;
	arl_last_computed_checksum = computed;
	if (!arl_current_result_mutated && valid)
		arl_physical_result_checksum = claimed;
	traceCommonFields("result_observed");
	fputs(",\"frame\":", arltrace_fp);
	traceJsonString(frame.c_str());
	fprintf(arltrace_fp,
	        ",\"claimed_checksum\":%d,\"computed_checksum\":%d,\"checksum_valid\":%s,\"checksum_class\":\"%s\",\"mutated\":%s}\n",
	        claimed, computed, valid ? "true" : "false",
	        claimed >= 0 && claimed <= 99 ? "low_000_099" : "high_100_255",
	        arl_current_result_mutated ? "true" : "false");
	arl_current_result_mutated = false;
	traceFlush();
}

bool CDirectSerial::buildEquivalentResult(const std::string &frame,
	                                      std::string &presented,
	                                      int &target_checksum)
{
	const ArlCorrectionResult result = arl_result_corrector.next(frame);
	if (!result.success) return false;
	presented = result.presented;
	target_checksum = result.presented_checksum;
	return result.original_checksum == arl_physical_result_checksum;
}

void CDirectSerial::traceResultCorrection(const std::string &original,
	                                      const std::string &presented,
	                                      int original_checksum,
	                                      int presented_checksum,
	                                      const char *reason)
{
	if (!arltrace_fp) return;
	traceCommonFields("result_correction");
	fputs(",\"original\":", arltrace_fp);
	traceJsonString(original.c_str());
	fputs(",\"presented\":", arltrace_fp);
	traceJsonString(presented.c_str());
	fprintf(arltrace_fp,
	        ",\"original_checksum\":%d,\"presented_checksum\":%d,"
	        "\"decimal_equal\":true,\"reason\":",
	        original_checksum, presented_checksum);
	traceJsonString(reason);
	fputs("}\n", arltrace_fp);
	traceFlush();
}

void CDirectSerial::traceObservedDecision(const char *decision) {
	if (!arltrace_fp) return;
	traceCommonFields("result_decision");
	fputs(",\"decision\":", arltrace_fp);
	traceJsonString(decision);
	fprintf(arltrace_fp,
	        ",\"claimed_checksum\":%d,\"computed_checksum\":%d}\n",
	        arl_last_claimed_checksum, arl_last_computed_checksum);
	traceFlush();
}


// setBreak(val) switches break on or off
void CDirectSerial::setBreak (bool value) {
	trace_break = value;
	SERIAL_setBREAK(comport,value);
	traceControlLines("break");
	traceHostState("host_control");
}

// updateModemControlLines(mcr) sets DTR and RTS. 
void CDirectSerial::setRTSDTR(bool rts, bool dtr) {
	const bool host_rts = arl_hold_rts ? true : rts;
	const bool host_dtr = arl_hold_dtr ? true : dtr;
	trace_rts = host_rts;
	trace_dtr = host_dtr;
	SERIAL_setRTS(comport,host_rts);
	SERIAL_setDTR(comport,host_dtr);
	traceControlLines("control");
	traceHostState("host_control");
}

void CDirectSerial::setRTS(bool val) {
	const bool host_rts = arl_hold_rts ? true : val;
	trace_rts = host_rts;
	SERIAL_setRTS(comport,host_rts);
	traceControlLines("control");
	traceHostState("host_control");
}

void CDirectSerial::setDTR(bool val) {
	const bool host_dtr = arl_hold_dtr ? true : val;
	trace_dtr = host_dtr;
	SERIAL_setDTR(comport,host_dtr);
	traceControlLines("control");
	traceHostState("host_control");
}

#endif
