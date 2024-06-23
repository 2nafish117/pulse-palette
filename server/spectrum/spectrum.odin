package spectrum

import "core:math/cmplx"
import "core:log"

// @TODO: https://en.wikipedia.org/wiki/Hann_function
// reference: https://github.com/tsoding/musializer/blob/master/src/plug.c
// @TODO: normalise the amplitudes of frequencies in 0-1 range?

analyse_spectrum :: proc(samples: []f32, allocator := context.temp_allocator) -> []f32 {
	complex_samples := make([]complex64, len(samples), allocator)
	defer delete(complex_samples, allocator)
	
	// copy into complex_samples
	for _, i in complex_samples {
		complex_samples[i] = samples[i]
	}

	fft(complex_samples)

	// copy into spectrum
	spectrum: []f32 = make([]f32, len(samples)/4, allocator)
	for _, i in spectrum {
		spectrum[i] = abs(complex_samples[i])
	}

	return spectrum
}