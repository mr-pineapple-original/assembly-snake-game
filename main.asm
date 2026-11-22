[org 0x0100]

jmp start

data_labels:
    snake_char:      db '*'      ; character used for each snake segment
    snake_attr:      db 0x07     ; attribute: light grey on black
    snake_start_length: dw 6        ; snake starts with 6 asterisks
    snake_start_row: dw 1        ; snake starts on row 1
    snake_start_col: dw 5        ; leftmost segment column
    snake_dir_row:      dw 0        ; row change per move  (-1 up, 0, +1 down)
    snake_dir_col:      dw 1        ; column change per move (-1 left, 0, +1 right)

    random_seeded:       dw 0       ; 0 = not seeded yet, 1 = already seeded
    random_seed:         dw 0       ; current value of the random generator

    fruit_char:         db 'F'      ; character used for the fruit
    fruit_attr:         db 0x0C     ; attribute: light red on black
    fruit_row:          dw 0        ; current fruit row    (set by get_fruit_position)
    fruit_col:          dw 0        ; current fruit column (set by get_fruit_position)

    game_over:          db 0        ; 0 = running, 1 = snake hit a wall

;  Fills the whole 80x25 text screen with black-on-grey spaces.
clrscr:
    push es
    push ax
    push cx
    push di

    mov ax,0xb800
    mov es,ax
    xor di,di
    mov ax,0x0720
    mov cx,2000

    cld
    rep stosw

    pop di
    pop cx
    pop ax
    pop es
    ret


;  Converts a (row, col) position into a video memory offset. Offset = (row * 80 + col) * 2     (2 bytes per cell)
;  [bp+4] = col, [bp+6] = row
calc_screen_offset:
    push bp
    mov bp, sp
    push bx

    mov al, [bp+6]              ; al = row
    mov bl, 80                  ; bl = screen width
    mul bl                      ; ax = al * bl = row * 80
    add ax, [bp+4]              ; ax = row * 80 + col
    shl ax, 1                   ; ax = cell number * 2 (char + attribute)

    pop bx
    pop bp
    ret 4


;  Draws a horizontal snake of '*' starting at (row, col).
;  [bp+4] = length, [bp+6] = col, [bp+8] = row
draw_snake:
    push bp
    mov bp, sp
    push es
    push ax
    push cx
    push di
;  Calculating where the head of snake goes in video memory 
    push word [bp+8]            ; parameter 1: row
    push word [bp+6]            ; parameter 2: col
    call calc_screen_offset     ; AX = byte offset
    mov di, ax                  ; DI = where we start writing

; Writing in the segments to show the snake on the screen
    mov ax, 0xb800
    mov es, ax                  ; es -> video memory
    mov al, [snake_char]        ; al = '*'
    mov ah, [snake_attr]        ; ah = colour attribute
    mov cx, [bp+4]              ; cx = number of segments
    cld
    rep stosw                   ; write ax to es:di, cx times

    pop di
    pop cx
    pop ax
    pop es
    pop bp
    ret 6

;  Generates a random number between 0 and n (0 and n are included).
;  First call sets the seed to low word of the BIOS timer tick count
;  Later calls sets the seed to seed = seed * 25173 + 13849  (an LCG)
;  Result at the end of this subroutine is seed mod (n + 1)
;  ax is used to store the result
;  [bp+4] = n, [bp+6] = result slot
random_range:
    push bp
    mov bp, sp
    push cx
    push dx 

    cmp word [random_seeded], 0
    jne .use_lcg                ; already seeded, so go update the seed

    ;first call to set the seed from the BIOS timer 
    mov ah, 0x00                ; int 0x1a, function 0 = read system timer
    int 0x1a                    ; returns tick count in cx:dx
    inc word [random_seeded]    ; to remember that we are seeded now
    mov [random_seed], dx       ; seed = low word of the tick count
    jmp .scale_result

.use_lcg:
    mov ax, 25173               ; LCG multiplier
    mul word [random_seed]      ; dx:ax = multiplier * seed
    add ax, 13849               ; add LCG increment
    mov [random_seed], ax       ; save the new seed (low 16 bits)

.scale_result:
    xor dx, dx                  ; clear dx for the division
    mov ax, [random_seed]       ; ax = seed (the dividend)
    shr ax, 1                   ; drops bit 0, which just flips every call
    mov cx, [bp+4]              ; cx = n
    inc cx                      ; cx = n + 1 (the divisor)
    div cx                      ; dx = seed mod (n + 1), in the range 0 ~ n
    mov ax, dx

    pop dx
    pop cx                     
    pop bp
    ret 2

;  Picks a random free spot inside the walls for the fruit.
;  If the spot is not empty (the snake is there), it picks again.
get_fruit_position:
    push ax
    push di
    push es

    mov ax, 0xb800
    mov es, ax                  ; es -> video memory (to read what is on screen)

.pick_again:
    push 77                     ; random column 0 ~ 77
    call random_range
    pop ax                      ; ax = 0 ~ 77
    inc ax                      ; ax = 1 ~ 78
    mov [fruit_col], ax

    push 22                     ; random row 0 ~ 22
    call random_range
    pop ax                      ; ax = 0 ~ 22
    inc ax                      ; ax = 1 ~ 23
    mov [fruit_row], ax

    ; checking if the the chosen cell is empty
    push word [fruit_row]
    push word [fruit_col]
    call calc_screen_offset     ; ax = byte offset of that cell
    mov di, ax
    cmp byte [es:di], ' '       ; is the character there a space?
    jne .pick_again             ; no, something is there, so pick again

    pop es
    pop di
    pop ax
    ret

;  Draws the fruit character at (row, col).
;  [bp+4] = col, [bp+6] = row
draw_fruit:
    push bp
    mov bp, sp
    push es
    push ax
    push di

    push word [bp+6]            ; parameter 1: row
    push word [bp+4]            ; parameter 2: col
    call calc_screen_offset     ; ax = byte offset
    mov di, ax                  ; di = where the fruit goes

    mov ax, 0xb800
    mov es, ax                  ; es -> video memory
    mov al, [fruit_char]        ; al = 'F'
    mov ah, [fruit_attr]        ; ah = colour attribute
    mov [es:di], ax             ; write character + attribute in one go

    pop di
    pop ax
    pop es
    pop bp
    ret 4

;  Writes one character + attribute cell at (row, col).
;  [bp+4] = cell (al = character, ah = attribute), [bp+6] = col, [bp+8] = row
draw_cell:
    push bp
    mov bp, sp
    push es
    push ax
    push di

    push word [bp+8]            ; parameter 1: row
    push word [bp+6]            ; parameter 2: col
    call calc_screen_offset     ; ax = byte offset
    mov di, ax                  ; di = cell position in video memory

    mov ax, 0xb800
    mov es, ax                  ; es -> video memory
    mov ax, [bp+4]              ; ax = character + attribute
    mov [es:di], ax

    pop di
    pop ax
    pop es
    pop bp
    ret 6

;  Fills snake_rows and snake_cols for the starting snake.
;  The snake lies horizontally and the head is the rightmost segment.
;  Segment i is at (start_row, start_col + length - 1 - i)
init_snake:
    push ax
    push bx
    push cx
    push si

    mov cx, [snake_start_length]
    mov [snake_length], cx      ; cx = number of segments to fill
    mov bx, [snake_start_row]   ; bx = row (same for every segment)
    mov ax, [snake_start_col]
    add ax, cx
    dec ax                      ; ax = column of the head
    xor si, si                  ; si = byte offset into the arrays (2 per entry)

.fill:
    mov [snake_rows + si], bx   ; store row of this segment
    mov [snake_cols + si], ax   ; store column of this segment
    dec ax                      ; next segment is one column to the left
    add si, 2                   ; next array entry (words are 2 bytes)
    loop .fill

    pop si
    pop cx
    pop bx
    pop ax
    ret

;  Reads one arrow key (if there is one) and changes the direction. If no key is pressed, the direction stays the same.
;  ( A turn straight back into the snake's own body is ignored ).
;  Scan codes: left 0x4B, right 0x4D, up 0x48, down 0x50
get_direction:
    push ax

    mov ah, 0x01                ; int 0x16, function 1 = is a key waiting?
    int 0x16
    jz .no_key                  ; zero flag set = no key, leave direction alone

    mov ah, 0x00                ; int 0x16, function 0 = read the key
    int 0x16                    ; ah = scan code

    cmp ah, 0x4B
    je .left
    cmp ah, 0x4D
    je .right
    cmp ah, 0x48
    je .up
    cmp ah, 0x50
    je .down
    jmp .flush                  ; some other key, ignore it

.left:
    cmp word [snake_dir_col], 1 ; moving right? then left is a reversal
    je .flush
    mov word [snake_dir_row], 0
    mov word [snake_dir_col], -1
    jmp .flush

.right:
    cmp word [snake_dir_col], -1
    je .flush
    mov word [snake_dir_row], 0
    mov word [snake_dir_col], 1
    jmp .flush

.up:
    cmp word [snake_dir_row], 1
    je .flush
    mov word [snake_dir_row], -1
    mov word [snake_dir_col], 0
    jmp .flush

.down:
    cmp word [snake_dir_row], -1
    je .flush
    mov word [snake_dir_row], 1
    mov word [snake_dir_col], 0

.flush:
    mov ax, 0x0C00              ; dos function 0Ch with al = 0: empty the key buffer
    int 0x21                    ; so only one turn can happen per move

.no_key:
    pop ax
    ret


;  Moves the snake one step in the current direction.
;  Works out for the new head position. If it is on a wall, set game_over and stop (the snake does not move)
;  Then erases the tail, shift every segment one place back and stores the new head then after that draws the new head.
move_snake:
    push ax
    push bx
    push cx
    push dx
    push si

    ; sets up new head = old head + direction
    mov ax, [snake_rows]
    add ax, [snake_dir_row]     ; ax = new head row
    mov bx, [snake_cols]
    add bx, [snake_dir_col]     ; bx = new head column

    ; checking for walls (walls are row 0, row 24, col 0, col 79)
    cmp ax, 0
    je .hit_wall
    cmp ax, 24
    je .hit_wall
    cmp bx, 0
    je .hit_wall
    cmp bx, 79
    je .hit_wall

    ; Erasing the tail
    mov si, [snake_length]
    dec si
    shl si, 1                   ; si = byte offset of the last segment
    push word [snake_rows + si] ; row of tail
    push word [snake_cols + si] ; col of tail
    push word 0x0720            ; a blank space
    call draw_cell

    ; Shift segments back (last = one before it, ... , segment 1 = head)
    mov cx, [snake_length]
    dec cx                      ; cx = number of segments that copy from the one in front
.shift:
    mov dx, [snake_rows + si - 2]
    mov [snake_rows + si], dx   ; row[i] = row[i-1]
    mov dx, [snake_cols + si - 2]
    mov [snake_cols + si], dx   ; col[i] = col[i-1]
    sub si, 2                   ; go one entry towards the head
    loop .shift

    ; To store the new head
    mov [snake_rows], ax
    mov [snake_cols], bx

    ; Drawing the new head
    push ax                     ; row
    push bx                     ; col
    mov ah, [snake_attr]
    mov al, [snake_char]        ; ax = '*' + attribute
    push ax
    call draw_cell
    jmp .done

.hit_wall:
    mov byte [game_over], 1

.done:
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

;  Waits for a number of BIOS timer ticks (1 tick is about 55 ms).
;  [bp+4] = ticks
delay:
    push bp
    mov bp, sp
    push ax
    push bx
    push cx
    push dx
    push si

    mov si, [bp+4]              ; si = ticks left to wait (int 0x1a changes cx, so not cx)
.next_tick:
    mov ah, 0x00
    int 0x1a                    ; dx = low word of the tick count
    mov bx, dx                  ; bx = tick count now
.poll:
    mov ah, 0x00
    int 0x1a
    cmp dx, bx
    je .poll                    ; same tick, keep waiting
    dec si
    jnz .next_tick

    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    pop bp
    ret 2

;  main subrotuine is the subroutine that manages everything 
;  For now: clear screen, draw snake, place and draw fruit, wait.
main:
    call clrscr

    push word [snake_start_row] ; row
    push word [snake_start_col] ; col
    push word [snake_start_length] ; length
    call draw_snake

    call get_fruit_position         

    push word [fruit_row]           ; row
    push word [fruit_col]           ; col
    call draw_fruit

.game_loop:
    push 2                          ; waits 2 ticks (about 0.1 s) between moves
    call delay
    call get_direction              ; checks if the player pressed an arrow key?
    call move_snake                 ; move one step
    cmp byte [game_over], 1
    jne .game_loop                  ; keep going until a wall is hit

    mov ah, 0                   ; TEMPORARY: wait for a key so we can
    int 0x16                    ; see the snake before exiting
    ret


start:
call main

end:
mov ax,0x4c00
int 0x21
