[org 0x0100]
data_labels:
    snake_char:      db '*'      ; character used for each snake segment
    snake_attr:      db 0x07     ; attribute: light grey on black
    snake_start_length: dw 6        ; snake starts with 6 asterisks
    snake_start_row: dw 1        ; snake starts on row 1
    snake_start_col: dw 5        ; leftmost segment column

jmp start


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
calc_screen_offset
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

;  main subrotuine is the subroutine that manages everything 
;  For now: clear screen, draw snake, wait.
main:
    call clrscr

    push word [snake_start_row] ; row
    push word [snake_start_col] ; col
    push word [snake_start_length] ; length
    call draw_snake

    mov ah, 0                   ; TEMPORARY: wait for a key so we can
    int 0x16                    ; see the snake before exiting
    ret
start:
call main

end:
mov ax,0x4c00
int 0x21
