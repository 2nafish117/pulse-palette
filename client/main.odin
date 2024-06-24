package main

import "core:log"
import "core:net"
import "core:time"
import "core:encoding/cbor"

import rl "vendor:raylib"

import ptl "soln:protocol"

WindowWidth :: 1280/2
WindowHeight :: 720/2

ClientConfig :: struct {

}

main :: proc() {
	context.logger = log.create_console_logger()

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

    rl.InitWindow(WindowWidth, WindowHeight, "live reaction")
    rl.SetTargetFPS(60)

    for !rl.WindowShouldClose() {

		// @TODO: make sure this buffer is big enough
		buffer: []byte = make([]byte, 1024 * 16, context.temp_allocator)
		bytes_read, remote_endpoint, err := net.recv_udp(socket.(net.UDP_Socket), buffer)

		packet: ptl.Packet
		the_err := ptl.unmarshal(buffer, &packet)

		log.infof("%v", the_err)

        rl.ClearBackground({0, 0, 0, 255})
        rl.BeginDrawing()
        
		if packet.spectrum_ext != nil && len(packet.spectrum_ext.spectrum_data.channel_data) > 0 {
			channel_data := packet.spectrum_ext.spectrum_data.channel_data
			for _, i in channel_data[0].spectrum {
				value := channel_data[0].spectrum[i]
				rl.DrawRectangle(100 + i32(i * 10), 100, 7, i32(value) * 3, rl.RED)
			}
		}
		
        rl.EndDrawing()
		free_all(context.temp_allocator)
    }

    rl.CloseWindow()
}