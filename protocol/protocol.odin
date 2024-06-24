package protocol

import "core:hash"
import "core:testing"
import "core:io"
import "core:bufio"
import "core:bytes"
import "core:fmt"
import "core:strconv"
import "core:encoding/cbor"
import "core:strings"
import "core:log"

Packet :: struct {
	header: Header,

	spectrum_ext: ^AudioSpectrumExt,
	sample_ext: ^AudioSampleExt,
}

PACKET_VERSION :: 69

Header :: struct {
	// continually increasing packet id
	// @TODO: what if server restarts? clients keeping track might get confused?
	// maybe use a magic to indicate the very first packet?
	packet_id: u64,
	// @TODO: how to version?
	packet_version: u32,
	packet_body_size: u32,
}

// audio spectrum extension
AudioSpectrumExt :: struct {
	spectrum_data: BatchSpectrumData,
}

BatchSpectrumData :: struct {
	batch_id: u64,
	sample_rate: int,
	channel_data: []ChannelSpectrumData,
}

ChannelSpectrumData :: struct {
	spectrum: []f32,
}

// audio sample extension
AudioSampleExt :: struct {
	sample_data: BatchSampleData,
}

BatchSampleData :: struct {
	batch_id: u64,
	sample_rate: int,
	channel_data: []ChannelSampleData,
}

ChannelSampleData :: struct {
	samples: []f32,
}

make_packet :: proc() -> Packet {
	@(static) packet_id: u64 = 0
	defer packet_id += 1

	return Packet{
		header = Header{
			packet_id = packet_id,
			packet_version = PACKET_VERSION,
		},
	}	
}

// @TODO: better error handling 	
marshal :: proc(p: ^Packet, allocator := context.temp_allocator) -> (data: []byte, err: cbor.Marshal_Error) {
	builder: strings.Builder
	strings.builder_init(&builder)

	// header
	cbor.marshal_into_builder(&builder, p.header) or_return
	
	// sample extension
	cbor.marshal_into_builder(&builder, b8(p.sample_ext != nil)) or_return
	if p.sample_ext != nil {
		cbor.marshal_into_builder(&builder, p.sample_ext^) or_return
	}

	// specctrum extension
	cbor.marshal_into_builder(&builder, b8(p.spectrum_ext != nil)) or_return
	if p.spectrum_ext != nil {
		cbor.marshal_into_builder(&builder, p.spectrum_ext^) or_return
	}

	// append crc
	crc := hash.crc32(builder.buf[:])
	cbor.marshal_into_builder(&builder, crc) or_return

	return builder.buf[:], nil
}

// @TODO: better error handling 
unmarshal :: proc(data: []byte, p: ^Packet, allocator := context.temp_allocator) -> cbor.Unmarshal_Error {
	buffer: bytes.Buffer
	bytes.buffer_init(&buffer, data)
	reader := io.to_reader(bytes.buffer_to_stream(&buffer))

	cbor.unmarshal_from_reader(reader, &p.header, cbor.Decoder_Flags{}, allocator) or_return

	sample_ext_used: b8
	cbor.unmarshal_from_reader(reader, &sample_ext_used, cbor.Decoder_Flags{}, allocator) or_return
	if sample_ext_used {
		p.sample_ext = new(AudioSampleExt, allocator)
		cbor.unmarshal_from_reader(reader, p.sample_ext, cbor.Decoder_Flags{}, allocator) or_return
	}

	spectrum_ext_used: b8
	cbor.unmarshal_from_reader(reader, &spectrum_ext_used, cbor.Decoder_Flags{}, allocator) or_return
	if spectrum_ext_used {
		p.spectrum_ext = new(AudioSpectrumExt, allocator)
		cbor.unmarshal_from_reader(reader, p.spectrum_ext, cbor.Decoder_Flags{}, allocator) or_return
	}

	crc: u32
	cbor.unmarshal_from_reader(reader, &crc) or_return

	// @TODO: clean this up
	if crc != hash.crc32(data[:len(data) - size_of(u32) - 1]) {
		log.error("crc check failed")
	}

	return nil
}