package main

import "core:hash"

Packet :: struct {
	header: Header,
	body: [^]byte,
	// flag to verify data integrity of header and body
	crc: u32,
}

Header :: struct {
	// continually increasing packet id
	// @TODO: what if server restarts? clients keeping track might get confused?
	// maybe use a magic to indicate the very first packet?
	packet_id: u64

	body_size: u16,
	unused1: [3]u16,
	
	// 8 extensins allowed, each extension can be customised to fit users requirement
	// it indexes into the body, any metadata/header needed for each extension can be put in the body allocated for the extsnsion,
	// extensions are ordered by the user, in the server
	// example extensions: audio-spectrum extm audio-samples ext, pixel ext
	extensions: [8]ExtEntry
}

ExtEntry :: struct {
	offset: u16,
	size: u16,
}

// audio spectrum extension
AudioSpectrumExt :: struct {
	spectrum_data: BatchSpectrumData,
}

ChannelSpectrumData :: struct {
	spectrum: []f32,
}

BatchSpectrumData :: struct {
	batch_id: u64,
	sample_rate: int,
	bin_size: int,
	channel_data: []ChannelSpectrumData,
}

// audio sample extension
AudioSampleExt :: struct {
	spectrum_data: BatchSpectrumData,
}

ChannelSampleData :: struct {
	samples: []f32,
}

BatchSampleData :: struct {
	batch_id: u64,
	sample_rate: int,
	channel_data: []ChannelSampleData,
}

make_packet :: proc(packet_id: u64) -> Packet {
	return Packet{
		packet_id = packet_id,
	}
}

add_extension :: proc(packet: ^Packet) {

}
