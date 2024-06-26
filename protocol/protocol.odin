package protocol

import "core:hash"
import "core:testing"
import "core:io"
import "core:bytes"
import "core:fmt"
import "core:strconv"
import "core:encoding/cbor"
import "core:strings"
import "core:log"
import "core:mem"
import "core:encoding/endian"
import "core:net"

Packet :: struct {
	header: Header,

	batch_id: u64,
	sample_rate: int,
	
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
	packet_version: u32,
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

write_header :: proc(w: io.Writer, val: ^Header, n_written: ^int = nil) -> (n: int, err: io.Error) {
	return io.write_ptr(w, val, size_of(Header), n_written)
}

read_header :: proc(r: io.Reader, val: ^Header, n_read: ^int = nil) -> (n: int, err: io.Error) {
	return io.read_ptr(r, val, size_of(Header), n_read)
}

// @TODO: better error handling 	
marshal :: proc(p: ^Packet, allocator := context.temp_allocator) -> (data: []byte, err: cbor.Marshal_Error) {
	buffer: bytes.Buffer
	bytes.buffer_init_allocator(&buffer, 0, 1024, allocator)

	writer := io.to_writer(bytes.buffer_to_stream(&buffer))

	_ = write_header(writer, &p.header) or_return

	_ = io.write_u64(writer, p.batch_id) or_return
	_ = io.write_u64(writer, cast(u64) p.sample_rate) or_return

	_ = io.write_u64(writer, cast(u64) len(p.sample_data)) or_return
	_ = io.write_ptr(writer, raw_data(p.sample_data), len(p.sample_data) * size_of(f32)) or_return

	_ = io.write_u64(writer, cast(u64) len(p.spectrum_data)) or_return
	_ = io.write_ptr(writer, raw_data(p.spectrum_data), len(p.spectrum_data) * size_of(f32)) or_return

	// append crc
	crc := hash.crc32(buffer.buf[:])
	_ = io.write_u64(writer, cast(u64) crc) or_return

	return buffer.buf[:], nil
}

// @TODO: better error handling 
unmarshal :: proc(data: []byte, p: ^Packet, allocator := context.temp_allocator) -> cbor.Unmarshal_Error {
	buffer: bytes.Reader
	bytes.reader_init(&buffer, data)

	reader := io.to_reader(bytes.reader_to_stream(&buffer))
	
	read_header(reader, &p.header)

	io.read_ptr(reader, &p.batch_id, size_of(u64))
	io.read_ptr(reader,  &p.sample_rate, size_of(u64))
	
	{
		arr_len: u64
		io.read_ptr(reader, &arr_len, size_of(u64)) or_return
		p.sample_data = make([]f32, arr_len, allocator)
		io.read_ptr(reader, raw_data(p.sample_data), len(p.sample_data) * size_of(f32)) or_return
	}

	{
		arr_len: u64
		io.read_ptr(reader, &arr_len, size_of(u64)) or_return
		p.spectrum_data = make([]f32, arr_len, allocator)
		io.read_ptr(reader, raw_data(p.spectrum_data), len(p.spectrum_data) * size_of(f32)) or_return
	}

	// @TODO: is there a better way to get the slice to calculate with?
	calculated_crc := hash.crc32(buffer.s[:len(buffer.s) - size_of(u64) - 1])

	crc: u64
	_ = io.read_ptr(reader, &crc, size_of(u64)) or_return
	
	if u32(crc) != calculated_crc {
		log.error("crc check failed")
	}

	return nil
}

@(test)
test_marshal_unmarsal :: proc(t: ^testing.T) {
	// @TODO: write test	
}