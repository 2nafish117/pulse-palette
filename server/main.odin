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

import spm "spectrum"

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
	channels: int,
	sample_rate: int,
	batch_sample_count: int,
	device_type: ma.device_type,
}

DEFAULT_SERVER_CONFIG :: ServerConfig{
	channels = 2,
	sample_rate = int(ma.standard_sample_rate.rate_44100),
	batch_sample_count = 1024,
	device_type = ma.device_type.loopback,
}

ChannelSampleData :: struct {
	samples: []f32,
}

BatchSampleData :: struct {
	batch_id: u64,
	channel_data: []ChannelSampleData,
}

ChannelSpectrumData :: struct {
	spectrum: []f32,
}

BatchSpectrumData :: struct {
	batch_id: u64,
	channel_data: []ChannelSpectrumData,
}

main :: proc() {
	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)

	cfg := DEFAULT_SERVER_CONFIG
	// @TODO: cmd params
	log.infof("using config %v", cfg)

	// @TODO: test capture devicetype
	assert(cfg.device_type == ma.device_type.loopback || cfg.device_type == ma.device_type.capture)

	// double the size because why not
	backing_memory_size := 2 * cfg.batch_sample_count
	backing_allocation : []f32 = make([]f32, backing_memory_size * cfg.channels)
	log.infof("using %v kB for ring buffer",  len(backing_allocation) * size_of(f32) / mem.Kilobyte)
	defer free(&backing_allocation)
	
	user_data : UserData
	log.info("initialising ring buffer")
	res := ma.pcm_rb_init(ma.format.f32, u32(cfg.channels), u32(backing_memory_size), raw_data(backing_allocation), nil, &user_data.samples_buffer)
	assert(res == ma.result.SUCCESS, "pcm ringbuffer couldn't be created")

	defer {
		log.info("uninitialising ring buffer")
		ma.pcm_rb_uninit(&user_data.samples_buffer)
	}

	device_config := ma.device_config_init(cfg.device_type)
	device_config.capture.format = ma.format.f32
	device_config.capture.channels = u32(cfg.channels)
	device_config.sampleRate = u32(cfg.sample_rate)
	device_config.dataCallback = data_callback
	device_config.pUserData = &user_data

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

	// @TODO: server loop

	
	rl.InitWindow(1280, 720, "pulse pallete")
	target_frame_rate := f32(cfg.sample_rate) / f32(cfg.batch_sample_count)
	log.infof("setting target frame rate for sample_rate: %v, batch_sample_count: %v, target_fps: %v", cfg.sample_rate, cfg.batch_sample_count, target_frame_rate)
	rl.SetTargetFPS(i32(target_frame_rate))

	for !rl.WindowShouldClose() {
		delta := rl.GetFrameTime()

		sample_data := get_sample_data(&cfg, &user_data)
		spectrum_data := calculate_spectrum_data(&cfg, &sample_data)
		// log.infof("%v", spectrum_data)

		rl.ClearBackground({16, 16, 16, 255})
		rl.BeginDrawing()

		// @TODO
		for _, i in spectrum_data.channel_data[0].spectrum {
			value := spectrum_data.channel_data[0].spectrum[i]
			rl.DrawRectangle(100 + i32(i * 10), 100, 7, i32(value) * 3, rl.RED)
		}

		rl.EndDrawing()

		free_all(context.temp_allocator)
	}

    rl.CloseWindow()
}

get_sample_data :: proc(cfg: ^ServerConfig, user_data: ^UserData) -> BatchSampleData {
	sample_data: BatchSampleData

	@(static) batch_id: u64 = 0
	buffer_out: rawptr
	num_frames_per_batch: u32 = u32(cfg.batch_sample_count)

	result := ma.pcm_rb_acquire_read(&user_data.samples_buffer, &num_frames_per_batch, &buffer_out)

	if result == ma.result.SUCCESS {
		
		// allocate mem for each channel
		sample_data.batch_id = batch_id
		sample_data.channel_data = make([]ChannelSampleData, cfg.channels, context.temp_allocator)
		for &channel in sample_data.channel_data {
			channel.samples = make([]f32, cfg.batch_sample_count, context.temp_allocator)
		}

		buffer_out_typed := transmute([^]f32)buffer_out

		log.infof("num_frames_per_batch: %v", num_frames_per_batch)

		j: int = 0
		// copy into each channel array
		for i: int = 0; i < int(num_frames_per_batch); i += cfg.channels {
			for c: int = 0; c < cfg.channels; c += 1 {
				value := buffer_out_typed[i + c]
				sample_data.channel_data[c].samples[j] = value
				j += 1
			}
		}
		
		batch_id += 1
		result_commit_read := ma.pcm_rb_commit_read(&user_data.samples_buffer, num_frames_per_batch, &buffer_out)
	}

	return sample_data
}

calculate_spectrum_data :: proc(cfg: ^ServerConfig, sample_data: ^BatchSampleData) -> BatchSpectrumData {
	spectrum_data: BatchSpectrumData
	spectrum_data.batch_id = sample_data.batch_id
	spectrum_data.channel_data = make([]ChannelSpectrumData, cfg.channels, context.temp_allocator)

	for _, i in spectrum_data.channel_data {
		channel_sample_data := sample_data.channel_data[i]
		spectrum_data.channel_data[i].spectrum = spm.analyse_spectrum(channel_sample_data.samples[:], context.temp_allocator)
	}

	return spectrum_data
}