#pragma once

/*
single header library to marshal and unmarshal packets
usage:

// include
#include <protocol.h>

// define
#define PROTOCOL_IMPL
#include <protocol.h>
*/

#ifndef PROTOCOL_IMPL 

#include <stdint.h>
#include <stdio.h>

#define PACKET_VERSION 69

typedef struct Header {
	// continually increasing packet id
	uint64_t packet_id;
	uint64_t packet_version;
} Header;

// @TODO: ensure a byte order, ensure network byte order (big endian)
typedef struct Packet {
	Header header;

	uint64_t batch_id;
	uint32_t sample_rate;
	
	float sample_data;
	uint32_t sample_data_len;

	float spectrum_data;
	uint32_t spectrum_data_len;
} Packet;

Packet make_packet();
void write_header(FILE* writer, Header* header, int* n_written);
void read_header(FILE* reader, Header* header, int* n_read);
void marshal(Packet* p, void* data, int* size);
void unmarshal(void* data, int size, Packet* p);

#else
// make packet with incremented packet_id, and filled in header
// this is to be used only when server is creating a new packet to send, not used by clients when they recieve
Packet make_packet() {
	static uint64_t packet_id = 0;

	Packet packet = {0};
  
	packet.header.packet_id = packet_id;
	packet.header.packet_version = PACKET_VERSION;

	packet_id += 1;
	return packet;
}

void write_header(FILE* writer, Header* header, int* n_written) {
	int _n_written = fwrite(header, sizeof(header), 1, writer);
	if(n_written) {
		*n_written = _n_written;
	}
}

void read_header(FILE* reader, Header* header, int* n_read) {
	int _n_read = fread(header, sizeof(header), 1, reader);
	if(n_read) {
		*n_read = _n_read;
	}
}

void marshal(Packet* p, void* data, int* size) {
	assert(p);
	assert(data);
	assert(size);

	FILE* writer = fmemopen(data, size, "w");

	write_header(writer, &p->header, NULL);

	fwrite(&p->batch_id, sizeof(p->batch_id), 1, writer);
	fwrite(&p->sample_rate, sizeof(p->sample_rate), 1, writer);

	{
		fwrite(&p->sample_data_len, sizeof(p->sample_data_len), 1, writer);
		fwrite(&p->sample_data, sizeof(p->sample_data), p->sample_data_len, writer);
	}

	{
		fwrite(&p->spectrum_data_len, sizeof(p->spectrum_data_len), 1, writer);
		fwrite(&p->spectrum_data, sizeof(p->spectrum_data), p->spectrum_data_len, writer);
	}

	// @TODO: calculate crc
	uint32_t crc = 0;
	fwrite(&crc, sizeof(crc), 1, writer);
}

void unmarshal(void* data, int size, Packet* p) {
	assert(data);
	assert(p);

	FILE* reader = fmemopen(data, size, "r");

	read_header(reader, &p->header, NULL);

	fread(&p->batch_id, sizeof(p->batch_id), 1, reader);
	fread(&p->sample_rate, sizeof(p->sample_rate), 1, reader);

	{
		fread(&p->sample_data_len, sizeof(p->sample_data_len), 1, reader);
		fread(&p->sample_data, sizeof(p->sample_data), p->sample_data_len, reader);
	}

	{
		fread(&p->spectrum_data_len, sizeof(p->spectrum_data_len), 1, reader);
		fread(&p->spectrum_data, sizeof(p->spectrum_data), p->spectrum_data_len, reader);
	}

	// @TODO: calculate crc and verify
	uint32_t crc = 0;
	fread(&crc, sizeof(crc), 1, reader);
}
#endif PROTOCOL_IMPL