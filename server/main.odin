package main

import "base:runtime"
import "core:fmt"
import "core:c"
import "core:log"
import "core:mem"
import "core:math"
import "core:math/cmplx"

import ma "vendor:miniaudio"
import rl "vendor:raylib"

// see docs
// https://raw.githubusercontent.com/mackron/miniaudio/master/miniaudio.h

thing : bool = false
data_callback :: proc "c" (pDevice : ^ma.device, pOutput : rawptr, pInput : rawptr, frameCount : u32) {
	// In playback mode copy data to pOutput. In capture mode read data from pInput. In full-duplex mode, both
	// pOutput and pInput will be valid and you can move data from pInput into pOutput. Never process more than
	// frameCount frames.

	frameCount := frameCount

	context = runtime.default_context()
	user_data : ^UserData = cast(^UserData)pDevice.pUserData
	write_ptr : rawptr
	result := ma.pcm_rb_acquire_write(&user_data.samples_buffer, &frameCount, &write_ptr)
	assert(result == ma.result.SUCCESS)

	write_ptr_typed := transmute([^]f32)write_ptr;
	input_ptr_typed := transmute([^]f32)pInput;
	
	// @TODO: maybe use memcpy here?
	for i in 0..< pDevice.capture.channels * frameCount {
		write_ptr_typed[i] = input_ptr_typed[i]
	}

	result2 := ma.pcm_rb_commit_write(&user_data.samples_buffer, frameCount, write_ptr)
	assert(result2 == ma.result.SUCCESS)
}

UserData :: struct {
	samples_buffer : ma.pcm_rb
}

ServerConfig :: struct {
	channels: u32,
	sample_rate: u32,
	group_duration: f32,
}

DEFAULT_SERVER_CONFIG :: ServerConfig{
	channels = 2,
	sample_rate = u32(ma.standard_sample_rate.rate_44100),
	group_duration = 0.01,
}

GroupFrameData :: struct {
	group_id: u64,
	channel_data: []GroupChannelData,
}

GroupChannelData :: struct {
	samples: [dynamic]f32,
}

main :: proc() {
	context.logger = log.create_console_logger()
	// meh not needed
	// defer log.destroy_console_logger(context.logger)

	cfg := DEFAULT_SERVER_CONFIG

	// @TODO: read from cfg file?

	// only 2 supported for now
	assert(cfg.channels == 2)

	BACKING_RINGBUFFER_FRAMES :: 1024 * 16
	backing_allocation : []f32 = make([]f32, BACKING_RINGBUFFER_FRAMES * cfg.channels)
	log.infof("using %v kB for ring buffer",  len(backing_allocation) * size_of(f32) / mem.Kilobyte)
	defer free(&backing_allocation)
	
	sample_data : UserData
	log.info("initialising ring buffer")
	res := ma.pcm_rb_init(ma.format.f32, cfg.channels, BACKING_RINGBUFFER_FRAMES, raw_data(backing_allocation), nil, &sample_data.samples_buffer)
	assert(res == ma.result.SUCCESS, "pcm ringbuffer couldn't be created")

	defer {
		log.info("uninitialising ring buffer")
		ma.pcm_rb_uninit(&sample_data.samples_buffer)
	}

	device_config := ma.device_config_init(ma.device_type.loopback)
	device_config.capture.format = ma.format.f32
	device_config.capture.channels = cfg.channels
	device_config.sampleRate = cfg.sample_rate
	device_config.dataCallback = data_callback
	device_config.pUserData = &sample_data

	device : ma.device
	log.infof("initialising device %v", transmute(cstring)&device.capture.name)
	if ma.device_init(nil, &device_config, &device) != ma.result.SUCCESS {
		panic("failed to initialise capture device")
	}

	defer {
		log.infof("uninitialising device %v", transmute(cstring)&device.capture.name)
		ma.device_uninit(&device)
	}

	if ma.device_start(&device) != ma.result.SUCCESS {
		ma.device_uninit(&device)
		panic("failed to start device")
	}

	group_id := u64(0)
	
	rl.InitWindow(1280, 720, "pulse pallete")
	// rl.SetTargetFPS(i32(1.0 / cfg.group_duration))
	rl.SetTargetFPS(60)

	group_frame_data: GroupFrameData

	for !rl.WindowShouldClose() {
		delta := rl.GetFrameTime()

		copied_data: []f32
		

		// num_frames_per_group: u32 = 4410
		num_frames_per_group: u32 = u32(f32(cfg.sample_rate) * cfg.group_duration)

		buffer_out: rawptr
		result := ma.pcm_rb_acquire_read(&sample_data.samples_buffer, &num_frames_per_group, &buffer_out)

		if result == ma.result.SUCCESS {
			
			copied_data = make([]f32, num_frames_per_group, context.temp_allocator)

			// fmt.printf("frame_group_id: %d num_frames_per_group: %d\n", frame_group_id, num_frames_per_group)
			buffer_out_typed := transmute([^]f32)buffer_out

			mem.copy_non_overlapping(raw_data(copied_data), buffer_out_typed, int(num_frames_per_group) * size_of(f32))
			
			group_id += 1

			result_commit_read := ma.pcm_rb_commit_read(&sample_data.samples_buffer, num_frames_per_group, &buffer_out)
		}

		rl.ClearBackground({0, 0, 0, 255})
		rl.BeginDrawing()

		// draw
		// for i := 0; i < int(num_frames_per_group); i += 2 {
		// 	sample := copied_data[i]
		// 	rl.DrawRectangle(i32(1 * i + 100), 100, 1, i32(sample * 500), rl.RED)
		// }

		// complex_data: []complex64 = make([]complex64, math.next_power_of_two(cast(int)num_frames_per_group), context.temp_allocator)
		// for i := 0; i < int(num_frames_per_group); i += 2 {
		// 	sample := copied_data[i]
		// 	complex_data[i] = complex(sample, 0)
		// }

		// fft(complex_data)

		// for i := 0; i < len(complex_data); i += 1 {
		// 	sample := cmplx.abs(complex_data[i])
		// 	rl.DrawRectangle(i32(1 * i + 100), 100, 1, i32(sample * 500), rl.RED)
		// }

		samples_test := make_sine_wave(2, 1, 2, 256, context.temp_allocator)
		samples_test2 := make_sine_wave(1, 32, 2, 256, context.temp_allocator)
		samples_test3 := make_sine_wave(1, 13, 2, 256, context.temp_allocator)
		samples_test4 := make_sine_wave(3, 74, 2, 256, context.temp_allocator)
		// log.infof("%v", samples_test)

		for s, i in samples_test {
			samples_test[i] = samples_test[i] + samples_test2[i] + samples_test3[i] + samples_test4[i]
		}

		for s, i in samples_test {
			rl.DrawRectangle(i32(i*2 + 100), 100, 2, i32(abs(real(s)) * 10.0), rl.RED)
		}

		fft(samples_test[:])

		for s, i in samples_test {
			rl.DrawRectangle(i32(i*2 + 100), 500, 2, i32((abs(s)+10) * 0.3), rl.RED)
		}


		rl.EndDrawing()

		free_all(context.temp_allocator)
	}

	rl.CloseWindow()    
}