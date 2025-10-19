org 0x100

%define MAX_LEN 200
%define MAX_WORDS 100
%define SPACE_CHAR 0x20
%define STDOUT 1
%define CR 0x0D
%define LF 0x0A

%define BUFFER_DATA (input_buffer + 2)

section .text
start:
    push cs
    pop ax
    mov ds, ax
    mov es, ax

    mov byte [input_buffer], MAX_LEN

    mov dx, start_msg
    mov ah, 0x09
    int 0x21

    mov dx, prompt_msg
    mov ah, 0x09
    int 0x21

    mov dx, input_buffer
    mov ah, 0x0A
    int 0x21

    xor ch, ch
    mov cl, [input_buffer + 1]
    mov [input_length], cx

    cmp cx, 0
    jne .have_chars
    mov dx, empty_msg
    mov ah, 0x09
    int 0x21
    jmp program_exit

.have_chars:
    call parse_words

    mov ax, [word_count]
    cmp ax, 0
    jne .maybe_sort
    mov dx, no_words_msg
    mov ah, 0x09
    int 0x21
    jmp program_exit

.maybe_sort:
    call sort_words

    mov dx, result_msg
    mov ah, 0x09
    int 0x21

    call build_output

    mov dx, BUFFER_DATA
    mov cx, [sorted_length]
    mov bx, STDOUT
    mov ah, 0x40
    int 0x21

program_exit:
    mov ax, 0x4C00
    int 0x21

; --------------------------------------
; Subroutines
; --------------------------------------

parse_words:
    xor bp, bp
    xor si, si
    mov cx, [input_length]

.skip_delims:
    cmp si, cx
    jae .done
    mov al, [si + BUFFER_DATA]
    cmp al, SPACE_CHAR
    jbe .advance
    mov di, si

.word_loop:
    cmp si, cx
    jae .store
    mov al, [si + BUFFER_DATA]
    cmp al, SPACE_CHAR
    jbe .store
    inc si
    jmp .word_loop

.store:
    mov ax, si
    sub ax, di
    mov bx, bp
    shl bx, 1
    mov [word_offsets + bx], di
    mov [word_lengths + bx], ax
    inc bp
    jmp .skip_delims

.advance:
    inc si
    jmp .skip_delims

.done:
    mov [word_count], bp
    ret

sort_words:
    mov ax, [word_count]
    cmp ax, 1
    jbe .finish

    xor si, si

.outer_loop:
    mov [min_index], si
    mov di, si
    inc di

.inner_loop:
    cmp di, [word_count]
    jae .evaluate_swap

    mov bx, [min_index]
    shl bx, 1
    mov ax, [word_offsets + bx]
    mov [offset1], ax
    mov ax, [word_lengths + bx]
    mov [length1], ax

    mov bx, di
    shl bx, 1
    mov ax, [word_offsets + bx]
    mov [offset2], ax
    mov ax, [word_lengths + bx]
    mov [length2], ax

    call compare_words
    cmp al, 0
    je .next_candidate
    mov [min_index], di

.next_candidate:
    inc di
    jmp .inner_loop

.evaluate_swap:
    mov bx, [min_index]
    cmp bx, si
    je .advance_outer
    mov [swap_first], si
    mov [swap_second], bx
    call swap_any

.advance_outer:
    inc si
    mov bx, [word_count]
    dec bx
    cmp si, bx
    jb .outer_loop

.finish:
    ret

compare_words:
    push bx
    push cx
    push dx
    push si
    push di
    push bp

    mov bx, [offset1]
    mov si, BUFFER_DATA
    add si, bx

    mov bx, [offset2]
    mov di, BUFFER_DATA
    add di, bx

    mov ax, [length1]
    mov bx, [length2]
    mov cx, ax
    cmp cx, bx
    jbe .min_ready
    mov cx, bx

.min_ready:
    jcxz .compare_lengths

.loop_chars:
    mov al, [si]
    mov dl, [di]
    cmp al, dl
    jne .diff
    inc si
    inc di
    loop .loop_chars

.compare_lengths:
    mov ax, [length1]
    mov bx, [length2]
    cmp ax, bx
    ja .first_greater
    xor al, al
    jmp .done

.diff:
    ja .first_greater
    xor al, al
    jmp .done

.first_greater:
    mov al, 1

.done:
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    ret

build_output:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp

    mov ax, [input_length]
    mov cx, ax
    jcxz .copy_ready
    cld
    mov si, BUFFER_DATA
    mov di, temp_buffer
    rep movsb

.copy_ready:
    mov cx, [word_count]
    mov bp, cx
    jcxz .prepare_empty

    mov di, word_lengths
    xor bx, bx

.sum_lengths:
    mov ax, [di]
    add bx, ax
    add di, 2
    loop .sum_lengths

    mov ax, bp
    cmp ax, 1
    jbe .spaces_done
    dec ax
    add bx, ax

.spaces_done:
    mov ax, bx
    add ax, 2
    mov [sorted_length], ax

    mov di, BUFFER_DATA
    add di, bx
    mov al, CR
    mov [di], al
    inc di
    mov al, LF
    mov [di], al
    dec di

    mov cx, bp

.copy_words:
    jcxz .finalize
    dec cx
    mov ax, cx
    shl ax, 1
    mov bx, word_lengths
    add bx, ax
    mov dx, [bx]
    mov bx, word_offsets
    add bx, ax
    mov si, [bx]
    add si, temp_buffer
    add si, dx
    dec si

.copy_single:
    cmp dx, 0
    je .word_done
    dec di
    mov al, [si]
    mov [di], al
    dec si
    dec dx
    jmp .copy_single

.word_done:
    cmp cx, 0
    je .copy_words
    dec di
    mov byte [di], SPACE_CHAR
    jmp .copy_words

.prepare_empty:
    mov ax, 2
    mov [sorted_length], ax
    mov di, BUFFER_DATA
    mov al, CR
    mov [di], al
    inc di
    mov al, LF
    mov [di], al
    jmp .finalize

.finalize:
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret


swap_any:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    mov bx, [swap_first]
    shl bx, 1
    mov ax, [word_offsets + bx]
    mov dx, [word_lengths + bx]

    mov di, [swap_second]
    shl di, 1
    mov cx, [word_offsets + di]
    mov si, [word_lengths + di]

    mov [word_offsets + bx], cx
    mov [word_offsets + di], ax
    mov [word_lengths + bx], si
    mov [word_lengths + di], dx

    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

section .data
start_msg db 'String sorter started.', CR, LF, '$'
prompt_msg db 'Enter a string (max 200 chars): $'
empty_msg db CR, LF, 'Input string is empty.', CR, LF, '$'
no_words_msg db CR, LF, 'No words to sort.', CR, LF, '$'
result_msg db CR, LF, 'Sorted string:', CR, LF, '$'

section .bss
input_buffer resb MAX_LEN + 2
input_length resw 1
word_count resw 1
sorted_length resw 1
word_offsets resw MAX_WORDS
word_lengths resw MAX_WORDS
offset1 resw 1
offset2 resw 1
length1 resw 1
length2 resw 1
min_index resw 1
swap_first resw 1
swap_second resw 1
temp_buffer resb MAX_LEN
