package main

import "core:log"
import "core:net"
import rl "vendor:raylib"

WindowWidth :: 1280
WindowHeight :: 720

input :: proc(delta: f32) {

}


tick :: proc(delta: f32) {

}


draw :: proc(delta: f32) {

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
	endpoint.address = net.IP4_Loopback
	endpoint.port = 6969
	net.bind(socket, endpoint)// or_else panic("unable to bind socket")

	log.infof("hellope")

	for true {
		log.infof("hellope")
		buffer: []byte = make([]byte, 1024, context.temp_allocator)
		bytes_read, remote_endpoint, err := net.recv_udp(socket.(net.UDP_Socket), buffer)
		log.infof("hellope")
		log.infof("read data: %v", buffer)

		free_all(context.temp_allocator)
	}

    // rl.InitWindow(WindowWidth, WindowHeight, "live reaction")
    // rl.SetTargetFPS(60)

    // thig : u32 = 0

    // for !rl.WindowShouldClose() {
    //     delta := rl.GetFrameTime()

    //     input(delta)
    //     tick(delta)

    //     rl.ClearBackground({0, 0, 0, 255})
    //     rl.BeginDrawing()
    //     draw(delta)
    //     rl.EndDrawing()
    // }

    // rl.CloseWindow()
}