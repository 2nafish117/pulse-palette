package main

import "core:log"
import "core:net"
import "core:time"
import "core:encoding/cbor"
import "core:bytes"
import "core:math"
import "core:mem"
import "core:thread"
import "core:sync"

import rl "vendor:raylib"

import ptl "soln:protocol"
import "soln:thirdparty/back"

WindowWidth :: 1280
WindowHeight :: 720

ClientConfig :: struct {
	recv_buffer_size: int
}

DEFAULT_CLIENT_CONFIG := ClientConfig{
	recv_buffer_size = 4096,
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

	app_main()
}

ThreadData :: struct {
	cfg: ClientConfig,
	packet: ^ptl.Packet,
	packet_mut: sync.Mutex,
}

recv_packet_work :: proc(data: rawptr) {
	console_logger := log.create_console_logger()
	context.logger = console_logger
	defer log.destroy_console_logger(console_logger)

	tdata := cast(^ThreadData) data
	cfg := tdata.cfg
	packet := tdata.packet

	socket := net.create_socket(.IP4, .UDP) or_else panic("failed to create udp socket")
	defer {
		log.infof("closing socket")
		net.close(socket)
	}

	endpoint: net.Endpoint
	endpoint.address = net.IP4_Any
	endpoint.port = 6969
	net.bind(socket, endpoint)// or_else panic("unable to bind socket")

	// we need to block
	// net.set_blocking(socket, false)

	recv_buffer_size := cfg.recv_buffer_size
	for {
		buffer: []byte = make([]byte, recv_buffer_size, context.temp_allocator)
			
		bytes_read, remote_endpoint, recv_err := net.recv_udp(socket.(net.UDP_Socket), buffer)
		if recv_err != nil {
			log.errorf("%v", recv_err)

			#partial switch err in recv_err {
				// attempt to resize buffer to accomodate the packet
				case net.UDP_Recv_Error: {
					// @TODO: check this behaviour in all platforms
					if err == net.UDP_Recv_Error.Buffer_Too_Small {
						// clamp how large this buffer can get
						new_recv_buffer_size := math.min(recv_buffer_size * 2, mem.Megabyte)
						if new_recv_buffer_size == recv_buffer_size {
							log.errorf("unable to grow the buffer past the defined maximum")
						} else {
							log.warnf("growing recv_buffer_sizefrom %v to %v to recieve all the packet data", recv_buffer_size, new_recv_buffer_size)
							recv_buffer_size = new_recv_buffer_size
						}
					}
				}
			}

			continue
		}
	
		// sync.lock(&tdata.packet_mut)
		// @TODO: this cannot be temp allocator, allocator must come from main thread? probalby
		unmarshal_err := ptl.unmarshal(buffer, packet, context.temp_allocator)
		// sync.unlock(&tdata.packet_mut)

		if unmarshal_err != nil {
			log.infof("%v", unmarshal_err)
			continue
		}

		free_all(context.temp_allocator)
	}
}

app_main :: proc() {
	cfg := DEFAULT_CLIENT_CONFIG
	

	rl.InitWindow(WindowWidth, WindowHeight, "live reaction")
	rl.SetTargetFPS(60)

	packet: ptl.Packet
	tdata: ThreadData = ThreadData{
		packet = &packet,
		cfg = cfg,
	}

	recv_thread := thread.create_and_start_with_data(&tdata, recv_packet_work)
	// defer  {
	// 	thread.join(recv_thread)
	// 	thread.destroy(recv_thread)
	// }

	for !rl.WindowShouldClose() {
		rl.ClearBackground({25, 25, 25, 255})
		rl.BeginDrawing()

		{
			// sync.lock(&tdata.packet_mut)
			// defer sync.unlock(&tdata.packet_mut)

			// @TODO: interpolation
			for _, i in packet.sample_data {
				value := packet.sample_data[i]
				rl.DrawRectangle(100 + i32(i * 1), 400, 1, i32(value * 50), rl.RED)
			}
	
			for _, i in packet.spectrum_data {
				value := packet.spectrum_data[i]
				rl.DrawRectangle(100 + i32(i * 1), 500, 1, i32(value * 2), rl.RED)
			}
		}

		rl.EndDrawing()
		free_all(context.temp_allocator)
	}

	rl.CloseWindow()

	// thread.terminate(recv_thread, 0)
	// thread.destroy(recv_thread)
}