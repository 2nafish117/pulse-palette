package main

import "base:runtime"
import "core:fmt"
import "core:c"
import "core:log"
import "core:mem"

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

main_ :: proc() {
    cfg := DEFAULT_SERVER_CONFIG

    BACKING_RINGBUFFER_FRAMES :: 1024 * 8
    backing_allocation : []f32 = make([]f32, BACKING_RINGBUFFER_FRAMES * cfg.channels)
    defer free(&backing_allocation)
    
    sample_data : UserData
    res := ma.pcm_rb_init(ma.format.f32, cfg.channels, BACKING_RINGBUFFER_FRAMES, raw_data(backing_allocation), nil, &sample_data.samples_buffer)
    assert(res == ma.result.SUCCESS, "pcm ringbuffer couldn't be created")
    defer ma.pcm_rb_uninit(&sample_data.samples_buffer)

    device_config := ma.device_config_init(ma.device_type.loopback)
    device_config.capture.format = ma.format.f32
    device_config.capture.channels = cfg.channels
    device_config.sampleRate = cfg.sample_rate
    device_config.dataCallback = data_callback
    device_config.pUserData = &sample_data

    device : ma.device
    if ma.device_init(nil, &device_config, &device) != ma.result.SUCCESS {
        panic("failed to initialise capture device")
    }
	defer ma.device_uninit(&device)

    if ma.device_start(&device) != ma.result.SUCCESS {
        ma.device_uninit(&device)
        panic("failed to start device")
    }

    fmt.println("we starting")

    frame_group_id := u64(0)
    
	rl.InitWindow(1280, 720, "live reaction")
    rl.SetTargetFPS(60)

    for !rl.WindowShouldClose() {
        delta := rl.GetFrameTime()

		copied_data: []f32

		// num_frames_per_group: u32 = 4410
		num_frames_per_group: u32 = u32(f32(cfg.sample_rate) * cfg.group_duration)

		buffer_out: rawptr
		result := ma.pcm_rb_acquire_read(&sample_data.samples_buffer, &num_frames_per_group, &buffer_out)

		if result == ma.result.SUCCESS {
			
			copied_data = make([]f32, num_frames_per_group, context.temp_allocator)

			fmt.printf("frame_group_id: %d num_frames_per_group: %d\n", frame_group_id, num_frames_per_group)
			buffer_out_typed := transmute([^]f32)buffer_out

			mem.copy_non_overlapping(raw_data(copied_data), buffer_out_typed, len(copied_data) * size_of(f32))
			
			// for i := u32(0); i < cfg.channels * num_frames_per_group; i += cfg.channels {
				
			// 	// reading only first channel
			// 	data := buffer_out_typed[i]
			// 	// fmt.printf("data: %f \n", data)
			// }
			frame_group_id += 1

			result_commit_read := ma.pcm_rb_commit_read(&sample_data.samples_buffer, num_frames_per_group, &buffer_out)
		}

        rl.ClearBackground({0, 0, 0, 255})
        rl.BeginDrawing()

		// draw
		for sample, i in copied_data {
			rl.DrawRectangle(i32(5 * i), 100, 5, i32(sample * 1000), rl.RED)
		}

        rl.EndDrawing()

		free_all(context.temp_allocator)
    }

    rl.CloseWindow()    
}