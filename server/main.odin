package main

import "core:fmt"
import ma "vendor:miniaudio"
import "core:c"
import "core:c/libc"
import "soln:viz"
import "base:runtime"
import "core:container/queue"

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
    frame_group_sample_count: u32,
}

DEFAULT_SERVER_CONFIG :: ServerConfig{
    channels=2, 
    sample_rate=u32(ma.standard_sample_rate.rate_44100),
    group_frame_count=4410,
}

main :: proc() {
    cfg := DEFAULT_SERVER_CONFIG

    BACKING_RINGBUFFER_FRAMES :: 1024 * 8
    backing_allocation : []f32 = make([]f32, BACKING_RINGBUFFER_FRAMES * cfg.channels)
    defer free(&backing_allocation)
    
    sample_data : UserData
    res := ma.pcm_rb_init(ma.format.f32, cfg.channels, BACKING_RINGBUFFER_FRAMES, raw_data(backing_allocation), nil, &sample_data.samples_buffer)
    assert(res == ma.result.SUCCESS, "pcm ringbuffer couldnt be created")
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

    if ma.device_start(&device) != ma.result.SUCCESS {
        ma.device_uninit(&device)
        panic("failed to start device")
    }

    fmt.println("we starting")

    frame_group_id := u64(0)
    running := true
    
    for running {
        num_frames_per_group: u32 = 4410
        // num_frames: u32 = u32(f32(device_config.sampleRate) * 0.01)

        buffer_out: rawptr
        result := ma.pcm_rb_acquire_read(&sample_data.samples_buffer, &num_frames_per_group, &buffer_out)

        if result == ma.result.SUCCESS {
            
            result_commit_read := ma.pcm_rb_commit_read(&sample_data.samples_buffer, num_frames_per_group, &buffer_out)    
        }


        result_commit_read := ma.pcm_rb_commit_read(&sample_data.samples_buffer, num_frames_per_group, &buffer_out)

        if result == ma.result.SUCCESS {
            #partial switch result_commit_read {
            case ma.result.SUCCESS:
                fmt.printf("frame_group_id: %d num_frames_per_group: %d\n", frame_group_id, num_frames_per_group)
                buffer_out_typed := transmute([^]f32)buffer_out

                for i := u32(0); i < cfg.channels * num_frames_per_group; i += cfg.channels {
                    
                    // reading only first channel
                    data := buffer_out_typed[i]
                    fmt.printf("data: %f \n", data)
                }
                frame_group_id += 1
                case ma.result.AT_END:
                    fmt.println("end of buffer")
                case:
                    fmt.println("hmm wtf happened? %d", result_commit_read)
                }
        }
    }

    fmt.println("we ending")

    ma.device_uninit(&device)
}