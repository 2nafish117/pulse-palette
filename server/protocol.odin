package main

import "core:hash"
import "core:testing"
import "core:io"
import "core:bufio"
import "core:bytes"
import "core:fmt"
import "core:strconv"

Packet :: struct {
	header: Header,
	body: []byte,
	// flag to verify data integrity of header and body
	crc: u32,
}

Header :: struct {
	// continually increasing packet id
	// @TODO: what if server restarts? clients keeping track might get confused?
	// maybe use a magic to indicate the very first packet?
	packet_id: u64,
	// @TODO: how to version?
	packet_version: u32,
	unused1: u16,
	body_size: u16,
	// 8 extensins allowed, each extension can be customised to fit users requirement
	// it indexes into the body, any metadata/header needed for each extension can be put in the body allocated for the extsnsion,
	// extensions are ordered by the user, in the server
	// example extensions: audio-spectrum extm audio-samples ext, pixel ext
	extensions: [8]ExtEntry,
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

PacketBuilder :: struct {

}

make_packet :: proc(packet_id: u64) -> Packet {
	return Packet{
		packet_id = packet_id,
	}
}

add_extension :: proc(packet: ^Packet, ext: ^AudioSampleExt) {
	assert(ext_slot >= 0 && ext_slot < 8, "max 8 extensions")

	
	packet.header.extensions[packet.header.extension_count].offset = packet.header.extension_count
	packet.header.extension_count += 1
}

@(test)
test_packet_builder :: proc(t: ^testing.T) {
	buffer: bytes.Buffer

	writer: io.Writer = bytes.buffer_to_stream(&buffer)


	fmt.println(buffer.buf)

	io.write_byte(writer, 69)

	fmt.println(buffer.buf)

	reader: io.Reader = bytes.buffer_to_stream(&buffer)

	the_byte: byte
	io.read_ptr(reader, &the_byte, size_of(the_byte))
	
	fmt.println(the_byte)

}