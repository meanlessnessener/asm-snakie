.global _start

.equ SYS_READ,  0
.equ SYS_WRITE, 1
.equ SYS_POLL,  7
.equ SYS_IOCTL, 16
.equ SYS_EXIT,  60

.equ TCGETS, 0x5401
.equ TCSETS, 0x5402

.equ ICANON, 0x0002
.equ ECHO,   0x0008

.data
termios_old_config: .skip 64
termios_new_config: .skip 64

pollfd:
    .long 0
    .short 1
    .short 0

cursor_10_lines_up: .ascii "\033[10A"
cursor_10_lines_up_len: .quad . - cursor_10_lines_up

map:
.ascii "------------------\n",
.ascii "|                |\n",
.ascii "|                |\n",
.ascii "|                |\n",
.ascii "|                |\n",
.ascii "|                |\n",
.ascii "|                |\n",
.ascii "|                |\n",
.ascii "|                |\n",
.ascii "------------------\n"
map_len: .quad . - map
map_width: .quad 19

game_over:
.ascii "       \033[1;31mGAME\033[0m       \n"
.ascii "       \033[1;31mOVER\033[0m       \n"
game_over_len: .quad . - game_over

output_buffer: .skip 256

.bss
snake_buffer: .skip 256 * 4 * 2
snake_head: .quad 0
snake_tail: .quad 0
apple: .long 0, 0
# 0, 1, 2, 3 == up left, down, right
direction: .byte 0
key: .byte 0
is_key_pressdown: .byte 0

first_write: .byte 0
rand: .long 0

.text

setup_termios:
    push %rbp
    movq %rsp, %rbp

    # read config
    movq $SYS_IOCTL, %rax
    movq $0, %rdi
    movq $TCGETS, %rsi
    leaq termios_old_config, %rdx
    syscall

    # make new config
    leaq termios_old_config, %rsi
    leaq termios_new_config, %rdi
    movq $64, %rcx
    rep movsb

    # erase ECHO and ICANON flags
    movl 12+termios_new_config, %eax
    andl $(~(ICANON | ECHO)), %eax
    movl %eax, 12+termios_new_config

    # set new config
    movq $SYS_IOCTL, %rax
    movq $0, %rdi
    movq $TCSETS, %rsi
    leaq termios_new_config, %rdx
    syscall

    leave
ret

restore_termios:
    push %rbp
    movq %rsp, %rbp

    movq $SYS_IOCTL, %rax
    movq $0, %rdi
    movq $TCSETS, %rsi
    leaq termios_old_config, %rdx
    syscall

    leave
ret

read_key:
    push %rbp
    movq %rsp, %rbp

    # get events
    movq $SYS_POLL, %rax
    leaq pollfd, %rdi
    movq $1, %rsi
    movq $150, %rdx
    syscall

    # are there any events
    movb $0, is_key_pressdown
    cmpq $0, %rax

    je read_key_exit
    movb $1, is_key_pressdown

    # read
    movq $SYS_READ, %rax
    movq $0, %rdi
    leaq key, %rsi
    movq $1, %rdx
    syscall

    read_key_exit:
    leave
ret

process_key:
    push %rbp
    movq %rsp, %rbp

    cmpb $1, is_key_pressdown
    jne process_key_exit

    cmpb $'q', key
    jne process_key_afterQ
        call exit
    process_key_afterQ:

    cmpb $'w', key
    jne process_key_afterW
        cmpb $2, direction
        je process_key_afterW
            movb $0, direction
            jmp process_key_exit
    process_key_afterW:

    cmpb $'a', key
    jne process_key_afterA
        cmpb $3, direction
        je process_key_afterA
            movb $1, direction
            jmp process_key_exit
    process_key_afterA:

    cmpb $'s', key
    jne process_key_afterS
        cmpb $0, direction
        je process_key_afterS
            movb $2, direction
            jmp process_key_exit
    process_key_afterS:

    cmpb $'d', key
    jne process_key_afterD
        cmpb $1, direction
        je process_key_afterD
            movb $3, direction
            jmp process_key_exit
    process_key_afterD:

    process_key_exit:
    leave
ret

__get_next_rand:
    push %rbp
    movq %rsp, %rbp

    # xorshift32 algo

    push %rax
    push %rcx
    movl rand, %eax

    movl %eax, %ecx
    shll $13, %ecx
    xorl %ecx, %eax

    movl %eax, %ecx
    shrl $17, %ecx
    xorl %ecx, %eax

    movl %eax, %ecx
    shll $5, %ecx
    xorl %ecx, %eax

    movl %eax, rand
    pop %rcx
    pop %rax

    leave
ret

__find_quad_in_snake:
    push %rbp
    movq %rsp, %rbp

    # rax = 8 bytes to search in snake
    # returns 1/0 in rax = found or not

    push %rdx
    push %rcx
    push %rdi

    movq %rax, %rdx
    xorq %rax, %rax

    movq snake_tail, %rcx

    snake_searching:
        movq snake_buffer(, %rcx, 8), %rdi

        cmpq %rdx, %rdi
        jne snake_searching_not_found_so_far
            movq $1, %rax
            jmp after_snake_searching
        snake_searching_not_found_so_far:

        cmpq %rcx, snake_head
        je after_snake_searching
        incb %cl
    jmp snake_searching
    after_snake_searching:

    pop %rdi
    pop %rcx
    pop %rdx

    leave
ret

update_snake:
    push %rbp
    movq %rsp, %rbp

    # copy head coordinates to next position on deque
    movq snake_head, %rdx
    movq snake_buffer(, %rdx, 8), %rax

    incq %rdx
    leaq snake_buffer(, %rdx, 8), %rdx
    movq %rax, (%rdx)
    # в rax кладем бошку, делаем шаг вперед и вставляем бошку, а еще rdx теперь адрес бошки

    cmpb $0, direction
    jne update_snake_after_up
        decl 0(%rdx)
    update_snake_after_up:

    cmpb $1, direction
    jne update_snake_after_left
        decl 4(%rdx)
    update_snake_after_left:

    cmpb $2, direction
    jne update_snake_after_down
        incl 0(%rdx)
    update_snake_after_down:

    cmpb $3, direction
    jne update_snake_after_right
        incl 4(%rdx)
    update_snake_after_right:

    # apply modulo 8 and 16 to new head coordinates
    andl $0x07, 0(%rdx)
    andl $0x0F, 4(%rdx)

    movq (%rdx), %rax
    call __find_quad_in_snake
    incb snake_head # наконец-то можно snake_head увеличить без попаболи
    cmpq $1, %rax
    jne update_snake_no_snake_self_intersection
        call update_screen

        movq $SYS_WRITE, %rax
        movq $1, %rdi
        leaq game_over, %rsi
        movq game_over_len, %rdx
        syscall

        call exit
    update_snake_no_snake_self_intersection:

    movq apple, %rax
    cmpq %rax, (%rdx)
    je update_snake_after_apple
        incb snake_tail
        jmp update_snake_exit
    update_snake_after_apple:
        # переместить apple
        apple_loop:
            call __get_next_rand
            xorq %rdx, %rdx
            movl rand, %edx
            andl $0x07, %edx
            movl %edx, apple

            call __get_next_rand
            xorq %rdx, %rdx
            movl rand, %edx
            andl $0x0F, %edx
            movl %edx, apple+4

            movq apple, %rax
            call __find_quad_in_snake
            cmp $1, %rax
            je apple_loop

    update_snake_exit:
    leave
ret

__place_char_to_buffer:
    push %rbp
    movq %rsp, %rbp

    # al = char
    # rdi = coordinates (row, column) 4 bytes each
    # rsi = addres to buffer
    # rdx = buffer_width

    # before was
    # rax = (buf[rsi][0] + 1) * width + (buf[rsi][1] + 1)
    # rcx iterates snake_tail -> snake_head, rsi = snake_buffer(, %rcx, 8)
    # xorq %rax, %rax
    # movl 0(%rsi), %eax
    # incq %rax
    # mulq map_width
    # addl 4(%rsi), %eax
    # incq %rax
    # movb $'#', output_buffer(%rax)

    push %rbx
    push %rax
    push %rdi
    push %rdx

    movb %al, %bl
    xorq %rax, %rax

    movl %edi, %eax
    incq %rax
    mulq %rdx
    shrq $32, %rdi
    addl %edi, %eax
    incq %rax
    movb %bl, (%rsi, %rax)

    pop %rdx
    pop %rdi
    pop %rax
    pop %rbx

    leave
ret

update_screen:
    push %rbp
    movq %rsp, %rbp

    # copy map to output_buffer
    leaq output_buffer, %rdi
    leaq map, %rsi
    movq map_len, %rcx
    rep movsb

    # place apple
    movb $'@', %al
    movq apple, %rdi
    leaq output_buffer, %rsi
    movq map_width, %rdx
    call __place_char_to_buffer

    # place snakie
    movq snake_tail, %rcx
    
    movb $'+', %al
    leaq output_buffer, %rsi
    movq map_width, %rdx

    snake_placement:
        movq snake_buffer(, %rcx, 8), %rdi
        call __place_char_to_buffer

        incb %cl
        cmpq %rcx, snake_head
        je update_screen_after_snake_placement
    jmp snake_placement
    update_screen_after_snake_placement:

    # place the head
    movb $'#', %al
    movq snake_buffer(, %rcx, 8), %rdi
    leaq output_buffer, %rsi
    movq map_width, %rdx
    call __place_char_to_buffer

    # begin to write

    cmpb $1, first_write
    je update_screen_write

    # place cursor in the beggining
    movq $SYS_WRITE, %rax
    movq $1, %rdi
    leaq cursor_10_lines_up, %rsi
    movq cursor_10_lines_up_len, %rdx
    syscall

    # write
    update_screen_write:
    movq $SYS_WRITE, %rax
    movq $1, %rdi
    leaq output_buffer, %rsi
    movq map_len, %rdx
    syscall

    movb $0, first_write
    leave
ret

setup_game:
    push %rbp
    movq %rsp, %rbp

    movb $3, direction

    movq $2, snake_head
    movq $0, snake_tail

    movl $4,  0+snake_buffer
    movl $5,  4+snake_buffer

    movl $4,  8+snake_buffer
    movl $6, 12+snake_buffer

    movl $4, 16+snake_buffer
    movl $7, 20+snake_buffer

    leave
ret

setup:
    push %rbp
    movq %rsp, %rbp

    call setup_termios
    call setup_game

    movb $1, first_write

    rdtsc
    xorl %edx, %eax
    cmpl %eax, %eax
    jnz setup_random_not_zero
    movl $0xdeadbeef, %eax
    setup_random_not_zero:
    movl %eax, rand

    leave
ret

update:
    push %rbp
    movq %rsp, %rbp

    call read_key
    call process_key
    call update_snake
    call update_screen

    leave
ret

exit:
    push %rbp
    movq %rsp, %rbp

    call restore_termios
    # exit
    movq $SYS_EXIT, %rax
    movq $0, %rdi
    syscall

    leave
ret

_start:
    call setup
    mainloop:
        call update
    jmp mainloop
