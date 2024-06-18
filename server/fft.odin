package main

import "core:fmt"
import "core:math"
import "core:math/cmplx"
import "base:intrinsics"

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
	// @TODO bit stuff here

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

@(private)
test_fft :: proc()
{
	data: []complex64 = { 1.0, 1.0, 1.0, 1.0, 0.0, 0.0, 0.0, 0.0 }

	// forward fft
	fft(data)

	fmt.printfln("fft: %v", data)

	// inverse fft
	ifft(data)

	fmt.printfln("ifft: %v", data)
}