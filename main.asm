[org 0x0100]

jmp start

data_labels:
    snake_char:      db '*'      ; character used for each snake segment
    snake_attr:      db 0x07     ; attribute: light grey on black
    snake_start_length: dw 6        ; snake starts with 6 asterisks
    snake_start_row: dw 1        ; snake starts on row 1
    snake_start_col: dw 5        ; leftmost segment column

    random_seeded:       dw 0       ; 0 = not seeded yet, 1 = already seeded
    random_seed:         dw 0       ; current value of the random generator

    fruit_char:         db 'F'      ; character used for the fruit
    fruit_attr:         db 0x0C     ; attribute: light red on black
    fruit_row:          dw 0        ; current fruit row    (set by get_fruit_position)
    fruit_col:          dw 0        ; current fruit column (set by get_fruit_position)

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

    mov ah, 0                   ; TEMPORARY: wait for a key so we can
    int 0x16                    ; see the snake before exiting
    ret


start:
call main

end:
mov ax,0x4c00
int 0x21
