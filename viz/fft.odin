package viz

import "core:fmt"
import "core:math"
import "core:math/cmplx"

@(private="file")
fft_internal :: proc(data: []f32, out: []complex64, n, s: int) {
    if n == 1 {
        out[0] = complex(data[0], 0)
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

fft :: proc(data: []f32, out: []complex64) {
    assert(len(data) == len(out))
    assert(math.is_power_of_two(len(data)))

    fft_internal(data, out, len(data), 1)
}

@(private="file")
test_fft :: proc() {
    
    x := []f32{1, 1, 1, 1, 0, 0, 0, 0}
    y := make([]complex64, len(x))

    fft(x, y)
    
    for v, c in y {
        fmt.printf("%f\n", v)
    }
}