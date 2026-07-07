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

#ifndef DOSBOX_LIBSERIAL_H
#define DOSBOX_LIBSERIAL_H

#include <string.h>

typedef struct _COMPORT *COMPORT;

struct SERIAL_host_state {
	bool available;
	int baudrate;
	char parity;
	int stopbits;
	int length;
	bool out_cts_flow;
	bool out_dsr_flow;
	bool dsr_sensitivity;
	bool out_x;
	bool in_x;
	bool abort_on_error;
	int dtr_control;
	int rts_control;
	unsigned long read_interval_timeout;
	unsigned long read_total_timeout_multiplier;
	unsigned long read_total_timeout_constant;
	unsigned long write_total_timeout_multiplier;
	unsigned long write_total_timeout_constant;
	int modem_status;
};

bool SERIAL_open(const char* portname, COMPORT* port);
void SERIAL_close(COMPORT port);
void SERIAL_getErrorString(char* buffer, size_t length);
bool SERIAL_getHostState(COMPORT port, SERIAL_host_state* state);

#define SERIAL_1STOP 1
#define SERIAL_2STOP 2
#define SERIAL_15STOP 0

// parity: n, o, e, m, s

bool SERIAL_setCommParameters(COMPORT port,
			int baudrate, char parity, int stopbits, int length);

void SERIAL_setDTR(COMPORT port, bool value);
void SERIAL_setRTS(COMPORT port, bool value);
void SERIAL_setBREAK(COMPORT port, bool value);

#define SERIAL_CTS 0x10
#define SERIAL_DSR 0x20
#define SERIAL_RI 0x40
#define SERIAL_CD 0x80

int SERIAL_getmodemstatus(COMPORT port);
bool SERIAL_setmodemcontrol(COMPORT port, int flags);

bool SERIAL_sendchar(COMPORT port, char data);

// 0-7 char data, higher=flags
#define SERIAL_BREAK_ERR 0x10
#define SERIAL_FRAMING_ERR 0x08
#define SERIAL_PARITY_ERR 0x04
#define SERIAL_OVERRUN_ERR 0x02

int SERIAL_getextchar(COMPORT port);

#endif
