package main

import "core:fmt"
import rl "vendor:raylib"

WindowWidth :: 1280
WindowHeight :: 720

input :: proc(delta: f32) {

}


tick :: proc(delta: f32) {

}


draw :: proc(delta: f32) {

}

main :: proc() {
    rl.InitWindow(WindowWidth, WindowHeight, "live reaction")
    rl.SetTargetFPS(60)

    for !rl.WindowShouldClose() {
        delta := rl.GetFrameTime()

        input(delta)
        tick(delta)

        rl.ClearBackground({0, 0, 0, 255})
        rl.BeginDrawing()
        draw(delta)
        rl.EndDrawing()
    }

    rl.CloseWindow()
}