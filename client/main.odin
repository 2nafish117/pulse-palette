package main

import "core:log"
import "core:net"
import "core:time"
import "core:encoding/cbor"

import rl "vendor:raylib"

import ptl "soln:protocol"
import "soln:thirdparty/back"

WindowWidth :: 1280
WindowHeight :: 720

ClientConfig :: struct {

}

main :: proc() {
	context.assertion_failure_proc = back.assertion_failure_proc
	back.register_segfault_handler()

	// set up tracking allocator
	track: back.Tracking_Allocator
	back.tracking_allocator_init(&track, context.allocator)
	defer back.tracking_allocator_destroy(&track)
	context.allocator = back.tracking_allocator(&track)
	defer back.tracking_allocator_print_results(&track)
	
	// init logger
	console_logger := log.create_console_logger()
	context.logger = console_logger
	defer log.destroy_console_logger(console_logger)

	{
		socket := net.create_socket(.IP4, .UDP) or_else panic("failed to create udp socket")
		defer {
			log.infof("closing socket")
			net.close(socket)
		}
	
		endpoint: net.Endpoint
		endpoint.address = net.IP4_Any
		endpoint.port = 6969
		net.bind(socket, endpoint)// or_else panic("unable to bind socket")
	
		// net.set_blocking(socket, false)

		rl.InitWindow(WindowWidth, WindowHeight, "live reaction")
		// rl.SetTargetFPS(60)
	
		for !rl.WindowShouldClose() {
	
			// @TODO: make sure this buffer is big enough
			buffer: []byte = make([]byte, 1024 * 1024, context.temp_allocator)
			bytes_read, remote_endpoint, err := net.recv_udp(socket.(net.UDP_Socket), buffer)
	
			// log.infof("buffer: %v", buffer)

			packet: ptl.Packet
			the_err := ptl.unmarshal(buffer, &packet)
	
			if the_err != nil {
				log.infof("%v", the_err)
			}

			rl.ClearBackground({0, 0, 0, 255})
			rl.BeginDrawing()
			
			if the_err == nil && packet.spectrum_ext != nil {
				channel_data := packet.spectrum_ext.spectrum_data.channel_data

				for _, i in channel_data[0].spectrum {
					value := channel_data[0].spectrum[i]
					rl.DrawRectangle(100 + i32(i * 1), 100, 1, i32(value * 2), rl.RED)
				}

				for _, i in channel_data[1].spectrum {
					value := channel_data[1].spectrum[i]
					rl.DrawRectangle(100 + i32(i * 1), 300, 1, i32(value * 2), rl.RED)
				}
			}
			
			rl.EndDrawing()
			free_all(context.temp_allocator)
		}
	
		rl.CloseWindow()
	}
}