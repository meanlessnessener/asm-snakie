# asm-snakie

Warning! The code is such a big mess because this is my first attempt to code in assembler (I'm glad I didn't shot myself while coding this). Maybe I'll refactor the code later... Also I didn't know what is PIE (=position independent executable), and so as you can see there's `-no-pie` argument :(

## About
Just a snake game written in assembler for x86-64 Linux. The game doesn't use libc, only bare syscalls

## Build
```bash
gcc -nostdlib -no-pie snakie.S -o snakie
```

## Run
```bash
./snakie
```

## Control
Move: WASD

Quit: Q
