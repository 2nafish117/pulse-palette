package protocol

import "core:hash"
import "core:io"
import "core:bytes"
import "core:log"
import "core:mem"
import "core:encoding/endian"
import "core:net"
import "core:math"
import "core:testing"

import "soln:server/spectrum"

Packet :: struct {
	header: Header,

	batch_id: u64,
	sample_rate: u32,
	
	sample_data: []f32,
	spectrum_data: []f32,
}

PACKET_VERSION :: 69

// @TODO: ensure a byte order, ensure network byte order (big endian)

Header :: struct {
	// continually increasing packet id
	// @TODO: what if server restarts? clients keeping track might get confused?
	// maybe use a magic to indicate the very first packet?
	packet_id: u64,
	// @TODO: how to version?
	packet_version: u64,
}

// make packet with incremented packet_id, and filled in header
// this is to be used only when server is creating a new packet to send, not used by clients when they recieve
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

write_header :: proc(w: io.Writer, val: ^Header, n_written: ^int = nil) -> (n: int, err: io.Error) {
	return io.write_ptr(w, val, size_of(Header), n_written)
}

read_header :: proc(r: io.Reader, val: ^Header, n_read: ^int = nil) -> (n: int, err: io.Error) {
	return io.read_ptr(r, val, size_of(Header), n_read)
}

// @TODO: better error handling 	
marshal :: proc(p: ^Packet, allocator := context.temp_allocator) -> (data: []byte, err: io.Error) {
	buffer: bytes.Buffer
	bytes.buffer_init_allocator(&buffer, 0, 4096, allocator)

	writer := io.to_writer(bytes.buffer_to_stream(&buffer))

	_ = write_header(writer, &p.header) or_return

	_ = io.write_ptr(writer, &p.batch_id, size_of(p.batch_id)) or_return
	_ = io.write_ptr(writer, &p.sample_rate, size_of(p.sample_rate)) or_return

	{
		arr_len: u32 = cast(u32) len(p.sample_data)
		_ = io.write_ptr(writer, &arr_len, size_of(u32)) or_return
		_ = io.write_ptr(writer, raw_data(p.sample_data), len(p.sample_data) * size_of(f32)) or_return
	}

	{
		arr_len: u32 = cast(u32) len(p.spectrum_data)
		_ = io.write_ptr(writer, &arr_len, size_of(u32)) or_return
		_ = io.write_ptr(writer, raw_data(p.spectrum_data), len(p.spectrum_data) * size_of(f32)) or_return
	}

	// append crc
	crc := hash.crc32(buffer.buf[:])
	_ = io.write_ptr(writer, &crc, size_of(crc)) or_return

	return buffer.buf[:], nil
}

// @TODO: better error handling 
unmarshal :: proc(data: []byte, p: ^Packet, allocator := context.temp_allocator) -> io.Error {
	buffer: bytes.Reader
	bytes.reader_init(&buffer, data)

	reader, ok := io.to_reader(bytes.reader_to_stream(&buffer))
	assert(ok)

	_ = read_header(reader, &p.header) or_return

	_ = io.read_ptr(reader, &p.batch_id, size_of(p.batch_id)) or_return
	_ = io.read_ptr(reader, &p.sample_rate, size_of(p.sample_rate)) or_return
	
	{
		arr_len: u32
		io.read_ptr(reader, &arr_len, size_of(arr_len)) or_return
		p.sample_data = make([]f32, arr_len, allocator)
		io.read_ptr(reader, raw_data(p.sample_data), len(p.sample_data) * size_of(f32)) or_return
	}

	{
		arr_len: u32
		io.read_ptr(reader, &arr_len, size_of(arr_len)) or_return
		p.spectrum_data = make([]f32, arr_len, allocator)
		io.read_ptr(reader, raw_data(p.spectrum_data), len(p.spectrum_data) * size_of(f32)) or_return
	}

	calculated_crc := hash.crc32(buffer.s[:len(buffer.s) - size_of(u32)])

	crc: u32
	_ = io.read_ptr(reader, &crc, size_of(u32)) or_return
	
	if crc != calculated_crc {
		log.error("crc check failed")
	}

	return nil
}

@(test)
test_protocol_marshal_unmarsal :: proc(t: ^testing.T) {
	context.logger = log.create_console_logger()
	// mock data
	sample_data := make_sine_wave_f32(1, 5, 1, 1024, context.temp_allocator)
	spectrum_data := make_sine_wave_f32(2, 10, 1, 1024, context.temp_allocator)

	packet := make_packet()
	packet.batch_id = 69
	packet.sample_rate = 420
	packet.sample_data = sample_data
	packet.spectrum_data = spectrum_data

	data, err: = marshal(&packet, context.temp_allocator)
	testing.expectf(t, err == nil, "marshalling error: %v", err)

	unmarshaled_packet: Packet
	unmarshal_err := unmarshal(data, &unmarshaled_packet, context.temp_allocator)
	testing.expectf(t, unmarshal_err == nil, "unmarshalling error: %v", unmarshal_err)

	testing.expectf(t, unmarshaled_packet.header == packet.header, "unmarshaled_packet.header expected: %v got: %v", packet.header, unmarshaled_packet.header)
	testing.expectf(t, unmarshaled_packet.batch_id == packet.batch_id, "unmarshaled_packet.batch_id expected: %v got: %v", packet.batch_id, unmarshaled_packet.batch_id)
	testing.expectf(t, unmarshaled_packet.sample_rate == packet.sample_rate, "unmarshaled_packet.sample_rate expected: %v got: %v", packet.sample_rate, unmarshaled_packet.sample_rate)

	testing.expectf(t, len(unmarshaled_packet.sample_data) == len(packet.sample_data), "unmarshaled_packet.sample_data len expected: %v got: %v", len(packet.sample_data), len(unmarshaled_packet.sample_data))
	for _, i in unmarshaled_packet.sample_data {
		testing.expectf(t, unmarshaled_packet.sample_data[i] == packet.sample_data[i], "unmarshaled_packet.sample_data[%v] expected: %v got: %v", i, packet.sample_data[i], unmarshaled_packet.sample_data[i])
	}

	testing.expectf(t, len(unmarshaled_packet.spectrum_data) == len(packet.spectrum_data), "unmarshaled_packet.spectrum_data len expected: %v got: %v", len(packet.spectrum_data), len(unmarshaled_packet.spectrum_data))
	for _, i in unmarshaled_packet.spectrum_data {
		testing.expectf(t, unmarshaled_packet.spectrum_data[i] == packet.spectrum_data[i], "unmarshaled_packet.spectrum_data[%v] expected: %v got: %v", i, packet.spectrum_data[i], unmarshaled_packet.spectrum_data[i])
	}
}

@(private = "file")
make_sine_wave_f32 :: proc(amp, freq, over_time: f32, num_samples: int, allocator := context.allocator) -> []f32 {
	samples := make([dynamic]f32, 0, num_samples, allocator)
	sample_period: f32 = over_time / f32(num_samples)

	for time: f32 = 0.0; time < over_time; time += sample_period {
		value := amp * math.sin(2 * math.PI * freq * time)
		append(&samples, value)
	}

	return samples[:]
}
