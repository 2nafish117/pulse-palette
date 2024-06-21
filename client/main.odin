package main

import "core:log"
import "core:net"
import "core:time"
import "core:encoding/cbor"
import "core:encoding/json"

import rl "vendor:raylib"

WindowWidth :: 1280
WindowHeight :: 720

// protocol structs

ChannelSpectrumData :: struct {
	spectrum: []f32,
}

BatchSpectrumData :: struct {
	batch_id: u64,
	channel_data: []ChannelSpectrumData,
}


// simpler struct for c
SpectrumPacketData :: struct {
	packet_id: u64,
	sample_rate: u32,
	spectrum_data: BatchSpectrumData,
	hello: u64,
}

main :: proc() {
	context.logger = log.create_console_logger()

	log.infof("hellope")
	socket := net.create_socket(.IP4, .UDP) or_else panic("failed to create udp socket")
	defer {
		log.infof("closing socket")
		net.close(socket)
	}

	endpoint: net.Endpoint
	endpoint.address = net.IP4_Any
	endpoint.port = 6969
	net.bind(socket, endpoint)// or_else panic("unable to bind socket")

	net.set_blocking(socket, false)

	// for true {
	// 	time.sleep(1 * time.Second)
	// 	buffer: []byte = make([]byte, 1024 * 8, context.temp_allocator)
	// 	log.info("hellope")
	// 	bytes_read, remote_endpoint, err := net.recv_udp(socket.(net.UDP_Socket), buffer)

	// 	packet_data: SpectrumPacketData
	// 	// cbor.unmarshal_from_string(transmute(string)buffer, &packet_data, cbor.Decoder_Flags{}, context.temp_allocator)
	// 	back_err := json.unmarshal(buffer, &packet_data, json.DEFAULT_SPECIFICATION, context.temp_allocator)
	// 	log.infof("read data: %v %v", packet_data, back_err)

	// 	free_all(context.temp_allocator)
	// }

    rl.InitWindow(WindowWidth, WindowHeight, "live reaction")
    rl.SetTargetFPS(60)

    thig : u32 = 0

    for !rl.WindowShouldClose() {

		// @TODO: make sure this buffer is big ewnought
		buffer: []byte = make([]byte, 1024 * 16, context.temp_allocator)
		bytes_read, remote_endpoint, err := net.recv_udp(socket.(net.UDP_Socket), buffer)

		packet_data: SpectrumPacketData
		// cbor.unmarshal_from_string(transmute(string)buffer, &packet_data, cbor.Decoder_Flags{}, context.temp_allocator)
		back_err := json.unmarshal(buffer, &packet_data, json.DEFAULT_SPECIFICATION, context.temp_allocator)
		// log.infof("read data: %v %v", packet_data, back_err)

		
        rl.ClearBackground({0, 0, 0, 255})
        rl.BeginDrawing()
        
		if len(packet_data.spectrum_data.channel_data) > 0 {

			for _, i in packet_data.spectrum_data.channel_data[0].spectrum {
				value := packet_data.spectrum_data.channel_data[0].spectrum[i]
				rl.DrawRectangle(100 + i32(i * 10), 100, 7, i32(value) * 3, rl.RED)
			}
		}
		
        rl.EndDrawing()
		free_all(context.temp_allocator)
    }

    rl.CloseWindow()
}