
stak SEGMENT STACK
    db 256 DUP (?)
stak ENDS
dats SEGMENT
    message db "A eto .EXE programma!", 0Dh, 0Ah, '$'
dats ENDS

cods SEGMENT
    ASSUME cs:cods, ds:dats, ss:stak

start:
    mov ax, dats
    mov ds, ax

    mov ah, 09h
    lea dx, message
    int 21h

    mov ah, 4Ch
    int 21h

cods ENDS

end start
