package main

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:net"
import "core:time"
import "core:sys/windows"

import ma "vendor:miniaudio"
import rl "vendor:raylib"

import spm "spectrum"
import ptl "soln:protocol"
import "soln:thirdparty/back"

// see docs
// https://raw.githubusercontent.com/mackron/miniaudio/master/miniaudio.h

UserData :: struct {
	samples_buffer : ma.pcm_rb,
}

ServerConfig :: struct {
	channels: int,
	sample_rate: int,
	batch_sample_count: int,
	device_type: ma.device_type,
	send_address: net.IP4_Address,
	send_port: int,

	use_sample_ext: bool,
	use_spectrum_ext: bool,
}

DEFAULT_SERVER_CONFIG :: ServerConfig{
	channels = 2,
	sample_rate = int(ma.standard_sample_rate.rate_44100),
	batch_sample_count = 1024,
	device_type = ma.device_type.loopback,
	
	send_address = net.IP4_Address{255, 255, 255, 255},
	send_port = 6969,

	use_sample_ext = false,
	use_spectrum_ext = true,
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

	// app logic
	{
		cfg := DEFAULT_SERVER_CONFIG
		// @TODO: cmd params
		log.infof("using config %v", cfg)
	
		// @TODO: test capture devicetype
		assert(cfg.device_type == ma.device_type.loopback || cfg.device_type == ma.device_type.capture)
	
		// double the size because why not
		backing_memory_size := 2 * cfg.batch_sample_count
		backing_allocation : []f32 = make([]f32, backing_memory_size * cfg.channels)
		log.infof("using %v kB for ring buffer",  len(backing_allocation) * size_of(f32) / mem.Kilobyte)
		defer delete(backing_allocation)
		
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
			panic("failed to start device")
		}
	
		when ODIN_OS == .Windows {
			// to get accurate_sleep to actually sleep accurately on windows
			windows.timeBeginPeriod(1)
		}
	
		socket := net.create_socket(.IP4, .UDP) or_else panic("failed to create udp socket")
		defer {
			log.infof("closing socket")
			net.close(socket)
		}
	
		// @TODO: why doesnt this or_else work?
		net.set_option(socket, .Broadcast, true)// or_else panic("could not set socket to broadcast")
	
		endpoint: net.Endpoint = {
			address = cfg.send_address,
			port = cfg.send_port,
		}
	
		// ugh the casts...
		target_frame_time := time.Duration(cast(i64)(f32(int(time.Second) * cfg.batch_sample_count) / f32(cfg.sample_rate)))
		log.infof("setting target frame time for sample_rate: %v, batch_sample_count: %v, target frame time: %v", cfg.sample_rate, cfg.batch_sample_count, target_frame_time)
	
		EMBEDDED_VISUALISE :: false
		when !EMBEDDED_VISUALISE {
			tick_now: time.Tick = time.tick_now()
			delta: time.Duration
		
			for {
				delta = time.tick_since(tick_now)
				tick_now = time.tick_now()
		
				// do all work
				{
					sample_data := get_sample_data(&cfg, &user_data)
					spectrum_data := calculate_spectrum_data(&cfg, &sample_data)
	
					packet := ptl.make_packet()
	
					if cfg.use_sample_ext {
						packet.sample_ext = new(ptl.AudioSampleExt, context.temp_allocator)
						packet.sample_ext.sample_data = sample_data
					}
	
					if cfg.use_spectrum_ext {
						packet.spectrum_ext = new(ptl.AudioSpectrumExt, context.temp_allocator)
						packet.spectrum_ext.spectrum_data = spectrum_data
					}
				
					data, err := ptl.marshal(&packet)
					net.send_udp(socket.(net.UDP_Socket), data, endpoint)
		
					other_packet: ptl.Packet
					err2 := ptl.unmarshal(data, &other_packet)
	
					free_all(context.temp_allocator)
				}
		
				// sleep for the remainder of time after some work is done
				work_ticks := time.tick_diff(tick_now, time.tick_now())
				assert(target_frame_time - work_ticks >= 0)
				time.accurate_sleep(target_frame_time - work_ticks)
			}
			
			when ODIN_OS == .Windows {
				// im done with windows wanting me to give me accurate sleeps
				windows.timeEndPeriod(1)
			}
		} else { // EMBEDDED_VISUALISE is true
			rl.InitWindow(1280, 720, "pulse pallete")
			rl.SetTargetFPS(i32(1.0 / time.duration_seconds(target_frame_time)))
	
			for !rl.WindowShouldClose() {
				delta := rl.GetFrameTime()
	
				sample_data := get_sample_data(&cfg, &user_data)
				spectrum_data := calculate_spectrum_data(&cfg, &sample_data)
				// log.infof("%v", spectrum_data)

				rl.ClearBackground({16, 16, 16, 255})
				rl.BeginDrawing()
	
				audio_visualise(&cfg, &sample_data, &spectrum_data)
				// sine_wave_visualise()

				// sine_wave_visualise2(&cfg)

				rl.EndDrawing()
	
				free_all(context.temp_allocator)
			}
	
			rl.CloseWindow()
		}
	}
}

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

	write_ptr_typed := transmute([^]f32)write_ptr
	input_ptr_typed := transmute([^]f32)pInput
	
	// @TODO: maybe use memcpy here?
	for i in 0..< pDevice.capture.channels * frameCount {
		write_ptr_typed[i] = input_ptr_typed[i]
	}

	result2 := ma.pcm_rb_commit_write(&user_data.samples_buffer, frameCount, write_ptr)
	assert(result2 == ma.result.SUCCESS)
}

get_sample_data :: proc(cfg: ^ServerConfig, user_data: ^UserData) -> ptl.BatchSampleData {
	sample_data: ptl.BatchSampleData

	@(static) batch_id: u64 = 0
	buffer_out: rawptr
	num_frames_per_batch: u32 = u32(cfg.batch_sample_count)

	result := ma.pcm_rb_acquire_read(&user_data.samples_buffer, &num_frames_per_batch, &buffer_out)

	if result == ma.result.SUCCESS {
		
		// allocate mem for each channel
		sample_data.batch_id = batch_id
		sample_data.channel_data = make([]ptl.ChannelSampleData, cfg.channels, context.temp_allocator)
		for &channel in sample_data.channel_data {
			channel.samples = make([]f32, cfg.batch_sample_count, context.temp_allocator)
		}

		buffer_out_typed := transmute([^]f32)buffer_out

		// log.infof("num_frames_per_batch: %v", num_frames_per_batch)

		// copy into each channel array
		j: int = 0
		for i: int = 0; i < int(num_frames_per_batch); i += cfg.channels {
			for c: int = 0; c < cfg.channels; c += 1 {
				value := buffer_out_typed[i + c]
				sample_data.channel_data[c].samples[j] = value
			}
			j += 1
		}
		
		batch_id += 1
		result_commit_read := ma.pcm_rb_commit_read(&user_data.samples_buffer, num_frames_per_batch, &buffer_out)
	}

	return sample_data
}

calculate_spectrum_data :: proc(cfg: ^ServerConfig, sample_data: ^ptl.BatchSampleData) -> ptl.BatchSpectrumData {
	spectrum_data: ptl.BatchSpectrumData
	spectrum_data.batch_id = sample_data.batch_id
	spectrum_data.channel_data = make([]ptl.ChannelSpectrumData, cfg.channels, context.temp_allocator)

	for _, i in spectrum_data.channel_data {
		channel_sample_data := sample_data.channel_data[i]
		spectrum_data.channel_data[i].spectrum = spm.analyse_spectrum(channel_sample_data.samples[:], context.temp_allocator)
	}

	return spectrum_data
}

@(private="file")
sine_wave_visualise :: proc() {
	samples := spm.make_sine_wave_f32(1, 22, 5, 256, context.temp_allocator)

	for _, i in samples {
		value := samples[i]
		rl.DrawRectangle(100 + i32(i * 4), 500, 4, 3 + i32(abs(value) * 50) , rl.RED)
	}

	spectrum := spm.analyse_spectrum(samples[:], context.temp_allocator)

	for _, i in spectrum {
		value := spectrum[i]
		rl.DrawRectangle(100 + i32(i * 2), 600, 2, 3 + i32(value * 0.5) , rl.RED)
	}

}

@(private="file")
sine_wave_visualise2 :: proc(cfg: ^ServerConfig) {
	samples := spm.make_sine_wave_f32(1, 22, 5, 256, context.temp_allocator)

	sample_data: ptl.BatchSampleData
	sample_data.batch_id = 56
	sample_data.channel_data = make([]ptl.ChannelSampleData, cfg.channels, context.temp_allocator)
	sample_data.channel_data[0].samples = samples[:]
	sample_data.channel_data[1].samples = samples[:]
	sample_data.sample_rate = cfg.sample_rate

	for _, i in samples {
		value := samples[i]
		rl.DrawRectangle(100 + i32(i * 4), 100, 4, 3 + i32(abs(value) * 50) , rl.RED)
	}

	spectrum_data := calculate_spectrum_data(cfg, &sample_data)
	// spectrum := spm.analyse_spectrum(samples[:], context.temp_allocator)

	for _, i in spectrum_data.channel_data[0].spectrum {
		value := spectrum_data.channel_data[0].spectrum[i]
		rl.DrawRectangle(100 + i32(i * 1), i32(300), 1, 2 + i32(value * 2), rl.RED)
	}
}

@(private="file")
audio_visualise :: proc(cfg: ^ServerConfig, sample_data: ^ptl.BatchSampleData, spectrum_data: ^ptl.BatchSpectrumData) {
	for c in 0..<cfg.channels {
		for _, i in sample_data.channel_data[0].samples {
			value := sample_data.channel_data[0].samples[i]
			rl.DrawRectangle(100 + i32(i * 1), i32(100 * c + 100), 1, i32(value * 100), rl.RED)
		}

		for _, i in spectrum_data.channel_data[0].spectrum {
			value := spectrum_data.channel_data[0].spectrum[i]
			rl.DrawRectangle(100 + i32(i * 1), i32(100 * c + 300), 1, i32(value * 2), rl.RED)
		}
	}
}