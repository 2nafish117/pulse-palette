package protocol 

import "core:encoding/cbor"
import "core:testing"
import "core:math"
import "core:fmt"

make_sine_wave_f32 :: proc(amp, freq, over_time: f32, num_samples: int, allocator := context.allocator) -> []f32 {
	samples := make([dynamic]f32, 0, num_samples, context.temp_allocator)
	sample_period: f32 = over_time / f32(num_samples)

	for time: f32 = 0.0; time < over_time; time += sample_period {
		value := amp * math.sin(2 * math.PI * freq * time)
		append(&samples, value)
	}

	return samples[:]
}

WaveData :: struct {
	wave_data: []f32,
}

@(test)
test_marshal_unmarsal_cbor :: proc(t: ^testing.T) {

	the_allocator := context.temp_allocator

	wave: WaveData
	wave.wave_data = make_sine_wave_f32(1, 5, 1, 4096, context.temp_allocator)
	
	the_bytes, err := cbor.marshal_into_bytes(wave, cbor.ENCODE_SMALL, the_allocator)
	testing.expectf(t, err == nil, "error in marshalling: %v", err)

	unmarshaled_wave: WaveData
	unmarshal_err := cbor.unmarshal_from_string(transmute(string)the_bytes, &unmarshaled_wave, cbor.Decoder_Flags{}, the_allocator)
	testing.expectf(t, unmarshal_err == nil, "error in unmarshalling: %v", unmarshal_err)
	
	testing.expect(t, len(wave.wave_data) == len(unmarshaled_wave.wave_data), "array length did not match")
	
	THRESH :: 1e-5
	for _, i in wave.wave_data {
		testing.expectf(t, 
			math.abs(wave.wave_data[i] - unmarshaled_wave.wave_data[i]) < THRESH, 
			"at index: %v expected %v got %v binary(expected %b, got %b)", 
			i, wave.wave_data[i], unmarshaled_wave.wave_data[i], 
			transmute(u32)wave.wave_data[i], transmute(u32)unmarshaled_wave.wave_data[i])
	}
}