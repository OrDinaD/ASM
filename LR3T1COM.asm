.model tiny
.code
    org 100h


start:
    mov ah, 09h
    lea dx, message
    int 21h
    
    ret
message db "ya sinsha", 0Dh, 0Ah, "$"
end start
    