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

    tail_row:           dw 0        ; where the tail was before the last move
    tail_col:           dw 0        ; (needed to grow the snake when it eats)

    random_seeded:       dw 0       ; 0 = not seeded yet, 1 = already seeded
    random_seed:         dw 0       ; current value of the random generator

    fruit_char:         db 'F'      ; character used for the fruit
    fruit_attr:         db 0x0C     ; attribute: light red on black
    fruit_row:          dw 0        ; current fruit row    (set by get_fruit_position)
    fruit_col:          dw 0        ; current fruit column (set by get_fruit_position)

    wall_char:          db '#'      ; character used for the walls
    wall_attr:          db 0x03     ; attribute: cyan on black

    score:              dw 0        ; current score
    score_label:        db 'Score:' ; drawn on the top wall, right corner

    speed_delay_ms:     dw 200      ; wait between moves in milliseconds (halved every 15 s)
    speed_interval:     dw 273      ; 15 seconds = about 273 BIOS ticks (18.2 per second)
    speed_last_tick:    dw 0        ; tick count when the speed last changed

    game_over:          db 0        ; 0 = running, 1 = snake hit a wall
    game_over_label:    db 'Score: '   ; 7 characters, shown at the center on game over

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
    mov dx, [snake_rows + si]
    mov [tail_row], dx          ; remember the tail position for growing
    mov dx, [snake_cols + si]
    mov [tail_col], dx
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

;  Draws the border around the screen: row 0, row 24, col 0, col 79.
draw_walls:
    push ax
    push bx

    mov ah, [wall_attr]
    mov al, [wall_char]         ; ax = wall cell (draw_cell keeps ax safe)

    xor bx, bx                  ; bx = column, 0..79
.horizontal:
    push 0                      ; top wall: row 0
    push bx
    push ax
    call draw_cell
    push 24                     ; bottom wall: row 24
    push bx
    push ax
    call draw_cell
    inc bx
    cmp bx, 80
    jne .horizontal

    mov bx, 1                   ; bx = row, 1..23 (corners are already drawn)
.vertical:
    push bx                     ; left wall: col 0
    push 0
    push ax
    call draw_cell
    push bx                     ; right wall: col 79
    push 79
    push ax
    call draw_cell
    inc bx
    cmp bx, 24
    jne .vertical

    pop bx
    pop ax
    ret


;  Adds 5 to the score.
update_score:
    add word [score], 5
    ret


;  Shows "Score:" and the number on the top wall, right corner.
;  Label of the word score is from column 67 to column 72 and the number starts at column 73.
display_score:
    push ax
    push bx
    push cx
    push dx
    push si

    ; draw the label, one character at a time
    xor si, si                  ; si = index into score_label
    mov cx, 6                   ; 6 characters
.label_loop:
    mov al, [score_label + si]
    mov ah, 0x0F                ; bright white
    mov dx, 67
    add dx, si                  ; dx = column for this character
    push 0                      ; row 0
    push dx                     ; col
    push ax                     ; cell
    call draw_cell
    inc si
    loop .label_loop

    ; splits the score into decimal digits (last digit comes out first)
    mov ax, [score]
    mov bx, 10
    xor cx, cx                  ; cx = number of digits
.split:
    xor dx, dx
    div bx                      ; ax = score / 10, dx = last digit
    push dx                     ; keep the digit on the stack
    inc cx
    cmp ax, 0
    jne .split

    ; pops the digits back so now the first digit comes out first
    mov si, 73                  ; si = column of the first digit
.print:
    pop ax                      ; al = digit 0..9
    add al, '0'                 ; convert to ASCII
    mov ah, 0x0E                ; yellow
    push 0                      ; row 0
    push si                     ; col
    push ax                     ; cell
    call draw_cell
    inc si
    loop .print

    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret


;  Gives the snake one more segment, at the spot the tail just left.
grow_snake:
    push ax
    push si

    mov si, [snake_length]
    shl si, 1                   ; si = byte offset of the new last segment
    mov ax, [tail_row]
    mov [snake_rows + si], ax
    mov ax, [tail_col]
    mov [snake_cols + si], ax
    inc word [snake_length]

    push word [tail_row]        ; draw it again cause move_snake had erased it
    push word [tail_col]
    mov ah, [snake_attr]
    mov al, [snake_char]
    push ax
    call draw_cell

    pop si
    pop ax
    ret


;  If the head is on the fruit then grow, add score, show score and place a new fruit.
check_fruit_eaten:
    push ax

    mov ax, [snake_rows]        ; head row
    cmp ax, [fruit_row]
    jne .done                   ; different row, not eaten
    mov ax, [snake_cols]        ; head column
    cmp ax, [fruit_col]
    jne .done                   ; different column, not eaten

    call grow_snake
    call update_score
    call display_score
    call get_fruit_position     ; after grow_snake, so it avoids the new tail too
    push word [fruit_row]
    push word [fruit_col]
    call draw_fruit

.done:
    pop ax
    ret

;  Clears the screen and shows "Score: N" in the center (row 12). The text is 7 + (number of digits) characters wide, so start column = 40 - (width / 2) keeps it centered.
game_over_screen:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    call clrscr

    ; split the score into digits (last digit first), keep them on the stack
    mov ax, [score]
    mov bx, 10
    xor cx, cx                  ; cx = number of digits
.split:
    xor dx, dx
    div bx                      ; ax = score / 10, dx = last digit
    push dx
    inc cx
    cmp ax, 0
    jne .split

    mov di, cx                  ; di = number of digits (cx is needed for loops)

    ; si = start column = 40 - (7 + digits) / 2
    mov ax, cx
    add ax, 7                   ; ax = total width of the text
    shr ax, 1                   ; ax = half of the width
    mov si, 40
    sub si, ax                  ; si = column of the first character

    ; draw "Score: " one character at a time
    mov cx, 7                   ; 7 characters in the label
    xor bx, bx                  ; bx = index into the label
.label_loop:
    mov al, [game_over_label + bx]
    mov ah, 0x0F                ; bright white
    push 12                     ; row 12
    push si                     ; col
    push ax                     ; cell
    call draw_cell
    inc si                      ; next column
    inc bx                      ; next character
    loop .label_loop

    ; draw the digits (they pop back in the right order)
    mov cx, di                  ; cx = number of digits
.digit_loop:
    pop ax                      ; al = digit 0 ~ 9
    add al, '0'                 ; convert to ASCII
    mov ah, 0x0E                ; yellow
    push 12
    push si
    push ax
    call draw_cell
    inc si
    loop .digit_loop

    pop di
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
    push cx
    push dx

    mov ax, [bp+4]              ; ax = milliseconds
    mov cx, 1000
    mul cx                      ; dx:ax = milliseconds * 1000 = microseconds
    mov cx, dx                  ; cx = high word of microseconds
    mov dx, ax                  ; dx = low word of microseconds
    mov ah, 0x86                ; int 0x15, function 0x86 = wait
    int 0x15

    pop dx
    pop cx
    pop ax
    pop bp
    ret 2

;  Starts the 15 second timer.
init_speed:
    push ax
    push cx
    push dx

    mov ah, 0x00                ; int 0x1a, function 0 = read system timer
    int 0x1a                    ; low word of the tick count is in dx
    mov [speed_last_tick], dx   ; the 15 seconds start counting from now

    pop dx
    pop cx
    pop ax
    ret

;  If 15 seconds have passed since the last speed change, halves the delay (the snake becomes twice as fast) but the delay never goes below speed_min_ms.
check_speed_up:
    push ax
    push dx

    mov ah, 0x00
    int 0x1a                    ; dx = current tick count (low word)
    mov ax, dx
    sub ax, [speed_last_tick]   ; ax = ticks since the last speed change
    cmp ax, [speed_interval]
    jb .done                    ; less than 15 seconds, nothing to do

    mov [speed_last_tick], dx   ; restart the 15 second timer
    shr word [speed_delay_ms], 1 ; delay / 2 = twice as fast

.done:
    pop dx
    pop cx
    pop ax
    ret


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

    call display_score             ; Shows score = 0 at the start
    call init_speed                ; Starts the 15 second timer

.game_loop:
    push word [speed_delay_ms]      ; wait the current delay (gets shorter over time)
    call delay
    call get_direction              ; checks if the player pressed an arrow key?
    call move_snake                 ; move one step
    call check_fruit_eaten
    call check_speed_up             ; every 15 seconds the snake gets twice as fast
    cmp byte [game_over], 1
    jne .game_loop                  ; keep going until a wall is hit

    call game_over_screen           ; clear screen, score in the center

    mov ax, 0x0C00                  ; empty the key buffer, so a key held while
    int 0x21                        ; dying does not close the screen instantly
    mov ah, 0x00                    ; wait for any key
    int 0x16

    call clrscr                     ; leave a clean screen for DOSBox
    mov ah, 0x02                    ; int 0x10, function 2 = set cursor position
    mov bh, 0                       ; page 0
    xor dx, dx                      ; dh = row 0, dl = column 0
    int 0x10
    ret


start:
call main

end:
mov ax,0x4c00
int 0x21
