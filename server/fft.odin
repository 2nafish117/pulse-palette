package main

import "base:intrinsics"
import "core:fmt"
import "core:math"
import "core:math/cmplx"
import "core:testing"
import "core:log"

@(private="file")
int_log2 :: proc "contextless" (x: int) -> u32 {
	x := x
	
	res: u32 = 0
	for x != 0 {
		x = x >> 1
		res += 1
	}

	return res - 1
}

// ported to odin from rosetta code
// Cooley-Tukey FFT (in-place, breadth-first, decimation-in-frequency)
fft :: proc(x: []complex64) {
	assert(math.is_power_of_two(len(x)))

	// DFT
	N: int = len(x)
	k: int = N

	theta := math.PI / f32(N)

	s, c := math.sincos(theta)
	// @TODO: cache this?
	phi: complex64 = complex(c, -s)

	for k > 1 {
		n: int = k
		k >>= 1
		phi = phi * phi
		T: complex64 = 1.0
		for l: int = 0; l < k; l += 1 {
			for a: int = l; a < N; a += n {
				b: int = a + k
				t: complex64 = x[a] - x[b]
				x[a] += x[b]
				x[b] = t * T
			}
			T = T * phi
		}
	}

	// Decimate
	m: u32 = int_log2(N)
	for a: u32 = 0; a < u32(N); a += 1 {
		b: u32 = a
		// Reverse bits
		b = (((b & 0xaaaaaaaa) >> 1) | ((b & 0x55555555) << 1))
		b = (((b & 0xcccccccc) >> 2) | ((b & 0x33333333) << 2))
		b = (((b & 0xf0f0f0f0) >> 4) | ((b & 0x0f0f0f0f) << 4))
		b = (((b & 0xff00ff00) >> 8) | ((b & 0x00ff00ff) << 8))
		b = ((b >> 16) | (b << 16)) >> (32 - m)
		if (b > a)
		{
			t: complex64 = x[a]
			x[a] = x[b]
			x[b] = t
		}
	}
}

// inverse fft (in-place)
ifft :: proc(x: []complex64) {
	assert(math.is_power_of_two(len(x)))

	// conjugate the complex numbers
	for &i in x {
		i = conj(i)
	}

	// forward fft
	fft(x)

	// conjugate the complex numbers again
	for &i in x {
		i = conj(i)
	}

	// scale the numbers
	for &i in x {
		i = i * complex(1.0 / f32(len(x)), 0)
	}
}



@(private="file")
fft_internal :: proc(data: []complex64, out: []complex64, n, s: int) {
    if n == 1 {
        out[0] = data[0]
        return
    }

    fft_internal(data, out, n/2, 2*s)
    fft_internal(data[s:], out[n/2:], n/2, 2*s)
    
    for k in 0..<n/2 {
        theta := -2 * math.PI * f32(k) / f32(n)
        tf := cmplx.rect_complex64(1, theta) * out[k + n/2]
        out[k], out[k + n/2] = out[k] + tf, out[k] - tf
    }
}

fft_recursive :: proc(data: []complex64, out: []complex64) {
    assert(len(data) == len(out))
    assert(math.is_power_of_two(len(data)))

    fft_internal(data, out, len(data), 1)
}


make_sine_wave :: proc(amp, freq, over_time: f32, num_samples: int, allocator := context.allocator) -> [dynamic]complex64 {
	samples := make([dynamic]complex64, 0, num_samples, context.temp_allocator)
	sample_period: f32 = over_time / f32(num_samples)

	for time: f32 = 0.0; time < over_time; time += sample_period {
		value := amp * math.sin(2 * math.PI * freq * time)
		append(&samples, value)
	}

	return samples
}

@(test)
test_fft :: proc(t: ^testing.T) {
	context.logger = log.create_console_logger()

	{
		threshold :: 1e-6
		samples: []complex64 = { 1.0, 1.0, 1.0, 1.0, 0.0, 0.0, 0.0, 0.0 }
		samples_copy := make([]complex64, len(samples), context.temp_allocator)
		copy(samples_copy, samples)

		fft(samples_copy)
		ifft(samples_copy)

		for s, i in samples {
			diff := s - samples_copy[i]
			testing.expect(t, math.abs(real(diff)) < threshold)
			testing.expect(t, math.abs(imag(diff)) < threshold)
		}
	}

	// {
	// 	amp :: 1
	// 	freq :: 1
	// 	over_time :: 2
	// 	num_samples :: 128

	// 	samples := make_sine_wave(amp, freq, over_time, num_samples, context.temp_allocator)
	// 	log.infof("%v", samples)
	// 	fft(samples[:])

	// 	sample_rate := f32(num_samples / over_time)
	// 	freq_bin_size := f32(sample_rate / num_samples)

	// 	for s, i in samples {
	// 		log.infof("bin: %v-%v -> %v", f32(i) * freq_bin_size, f32(i+1) * freq_bin_size, abs(s))
	// 	}
	// }

	// {
	// 	amp :: 2
	// 	freq :: 3.5
	// 	over_time :: 1
	// 	num_samples :: 128

	// 	samples := make_sine_wave(amp, freq, over_time, num_samples, context.temp_allocator)
	// 	log.infof("%v", samples)
	// 	fft(samples[:])

	// 	sample_rate := f32(num_samples / over_time)
	// 	freq_bin_size := f32(sample_rate / num_samples)

	// 	for s, i in samples {
	// 		log.infof("bin: %v-%v -> %v", f32(i) * freq_bin_size, f32(i+1) * freq_bin_size, abs(s))
	// 	}
	// }

	{
		num_samples :: 256
		over_time :: 2
		samples1 := make_sine_wave(1, 78, over_time, num_samples, context.temp_allocator)
		samples2 := make_sine_wave(1, 100, over_time, num_samples, context.temp_allocator)

		samples := make([dynamic]complex64, context.temp_allocator)
		for i, _ in 0..<len(samples1) {
			append(&samples, samples1[i] + samples2[2])
		}

		out := make([]complex64, num_samples, context.temp_allocator)
		fft_recursive(samples[:], out)

		fft(samples[:])

		sample_rate := f32(num_samples / over_time)
		freq_bin_size := f32(sample_rate / num_samples)

		for s, i in samples {
			diff := abs(s) - abs(out[i])
			log.infof("bin: %v-%v %v            -> %v (%v) diff (%v)", f32(i) * freq_bin_size, f32(i+1) * freq_bin_size, real(s), abs(s), abs(out[i]), abs(diff) < 1e-5)
		}
	}

	free_all(context.temp_allocator)
}