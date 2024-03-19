package main

import "core:fmt"
import ma "vendor:miniaudio"
import "core:c"
import "core:c/libc"
import "soln:viz"

data_callback :: proc "c" (pDevice : ^ma.device, pOutput : rawptr, pInput : rawptr, frameCount : u32) {
    // In playback mode copy data to pOutput. In capture mode read data from pInput. In full-duplex mode, both
    // pOutput and pInput will be valid and you can move data from pInput into pOutput. Never process more than
    // frameCount frames.

    pEncoder : ^ma.encoder = cast(^ma.encoder)pDevice.pUserData
    ma.encoder_write_pcm_frames(pEncoder, pInput, u64(frameCount), nil)
}

main :: proc() {

    encoder_config := ma.encoder_config_init(ma.encoding_format.wav, ma.format.f32, 2, cast(u32)ma.standard_sample_rate.rate_44100)

    encoder : ma.encoder
    if ma.encoder_init_file("test.mp3", &encoder_config, &encoder) != ma.result.SUCCESS {
        panic("failed to initialise output file")
    }

    // device_data_proc :: proc "c" (pDevice: ^device, pOutput, pInput: rawptr, frameCount: u32)

    device_config := ma.device_config_init(ma.device_type.loopback)
    device_config.capture.format = encoder.config.format
    device_config.capture.channels = encoder.config.channels
    device_config.sampleRate = encoder.config.sampleRate
    device_config.dataCallback = data_callback
    device_config.pUserData = &encoder

    device : ma.device
    if ma.device_init(nil, &device_config, &device) != ma.result.SUCCESS {
        panic("failed to initialise capture device")
    }

    if ma.device_start(&device) != ma.result.SUCCESS {
        ma.device_uninit(&device)
        panic("failed to start device")
    }

    fmt.print("yo we in buidness")

    libc.getchar()

    ma.device_uninit(&device)
    ma.encoder_uninit(&encoder)
}