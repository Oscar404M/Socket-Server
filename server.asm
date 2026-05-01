; Standalone x64 MASM Web Server
; Assemble: ml64 /c server.asm
; link /subsystem:console /entry:main server.obj kernel32.lib ws2_32.lib msvcrt.lib ucrt.lib legacy_stdio_definitions.lib

include imports.inc

; ==============================================================================
; INITIALIZED DATA SEGMENT
; ==============================================================================
.DATA
str_wsa_fail        db 'WSAStartup failed.', 10, 0
str_iocp_run        db 'IOCP Server running at 127.0.0.1:8888', 10, 0
str_ip              db '127.0.0.1', 0
str_welcome         db 'Welcome to Oscar server!', 10, 0
str_initial_fail    db 'Initial WSARecv failed.', 10, 0
str_new_client      db 'New client connected: fd %llu', 10, 0
str_recv_fail       db 'WSARecv failed with error %d', 10, 0
str_received        db 'Received from fd %llu: %s', 10, 0
str_disconnected    db 'Client disconnected on fd %llu', 10, 0

; ==============================================================================
; CODE SEGMENT
; ==============================================================================
.CODE

; ------------------------------------------------------------------------------
; DWORD WINAPI ServerWorkerThread(LPVOID CompletionPortID)
; ------------------------------------------------------------------------------
ServerWorkerThread PROC
    ; --- Prologue ---
    mov     [rsp+16], rbx          ; Save non-volatile registers to shadow space
    mov     [rsp+24], rsi
    push    rdi                    ; rsp -= 8 (Total offset: 8 + 8(ret) = 16)
    sub     rsp, 96                ; rsp -= 96 (Total offset: 112 -> 112 % 16 == 0. Stack ALIGNED)

    xor     esi, esi               ; Zero out esi for quick 0 values
    mov     rbx, rcx               ; rbx = CompletionPortID

    ; Initialize variables on stack
    mov     qword ptr [rsp+80], rsi ; CompletionKey = 0
    mov     dword ptr [rsp+72], esi ; BytesTransferred = 0
    mov     qword ptr [rsp+64], rsi ; PerIoData = NULL
    mov     dword ptr [rsp+76], esi ; Flags = 0

worker_loop:
    ; 1. GetQueuedCompletionStatus(...)
    lea     r9, [rsp+64]           ; &PerIoData
    mov     dword ptr [rsp+32], -1 ; INFINITE wait
    lea     r8, [rsp+80]           ; &CompletionKey
    mov     rcx, rbx               ; CompletionPort
    lea     rdx, [rsp+72]          ; &BytesTransferred
    call    GetQueuedCompletionStatus

    test    eax, eax
    je      check_disconnect
    cmp     dword ptr [rsp+72], esi ; if (BytesTransferred == 0)
    je      check_disconnect

    ; 2. printf("Received from fd %llu: %s\n", PerIoData->Socket, PerIoData->Buffer)
    mov     rdx, [rsp+64]          ; rdx = PerIoData
    lea     rcx, str_received
    lea     r8, [rdx+48]           ; PerIoData->Buffer (offset 48)
    mov     rdx, [rdx+1072]        ; PerIoData->Socket (offset 1072)
    call    printf

    ; 3. Setup PerIoData for next WSARecv
    mov     rdi, [rsp+64]          ; rdi = PerIoData
    mov     dword ptr [rdi+32], 1024 ; PerIoData->DataBuf.len = 1024
    lea     rax, [rdi+48]          
    mov     qword ptr [rdi+40], rax  ; PerIoData->DataBuf.buf = PerIoData->Buffer

    ; 4. SecureZeroMemory(PerIoData->Buffer, DATA_BUFSIZE)
    xor     eax, eax
    mov     rcx, 1024
    lea     rdi, [rdi+48]          ; rdi = PerIoData->Buffer
    rep stosb                      ; inline zeroing memory

    ; 5. WSARecv(...)
    lea     r9, [rsp+72]           ; &BytesTransferred
    mov     qword ptr [rsp+48], 0  ; NULL (CompletionRoutine)
    mov     r8d, 1                 ; dwBufferCount = 1
    mov     rcx, [rsp+64]          ; rcx = PerIoData
    lea     rax, [rsp+76]          ; &Flags
    mov     [rsp+40], rcx          ; lpOverlapped (&PerIoData->Overlapped which is offset 0)
    mov     dword ptr [rsp+76], esi ; Flags = 0
    mov     [rsp+32], rax          ; &Flags
    lea     rdx, [rcx+32]          ; &PerIoData->DataBuf
    mov     rcx, [rcx+1072]        ; PerIoData->Socket
    call    WSARecv

    cmp     eax, -1
    jne     worker_loop

    call    WSAGetLastError
    cmp     eax, 997               ; WSA_IO_PENDING
    je      worker_loop

    ; 6. Print Error on WSARecv
    call    WSAGetLastError
    mov     edx, eax
    lea     rcx, str_recv_fail
    call    printf
    jmp     worker_loop

check_disconnect:
    mov     rdx, [rsp+64]          ; PerIoData
    test    rdx, rdx
    je      worker_loop

    ; 7. Client Disconnected
    mov     rdx, [rdx+1072]        ; PerIoData->Socket
    lea     rcx, str_disconnected
    call    printf

    mov     rcx, [rsp+64]          
    mov     rcx, [rcx+1072]        ; PerIoData->Socket
    call    closesocket            ; closesocket(PerIoData->Socket)

    mov     rcx, [rsp+64]
    call    GlobalFree             ; GlobalFree(PerIoData)

    jmp     worker_loop

    ; --- Epilogue (Unreachable theoretically due to infinite loop) ---
    add     rsp, 96
    pop     rdi
    mov     rsi, [rsp+24]
    mov     rbx, [rsp+16]
    ret
ServerWorkerThread ENDP

; ------------------------------------------------------------------------------
; int main()
; ------------------------------------------------------------------------------
PUBLIC main
main PROC
    ; --- Prologue ---
    push    rsi
    push    rdi
    sub     rsp, 584               ; 584 + 8(rdi) + 8(rsi) + 8(ret) = 608 % 16 == 0. Stack ALIGNED.

    ; 1. WSAStartup
    mov     ecx, 514               ; MAKEWORD(2, 2) = 0x0202
    lea     rdx, [rsp+144]         ; &wsaData
    call    WSAStartup
    test    eax, eax
    je      wsa_ok

    lea     rcx, str_wsa_fail
    call    printf
    jmp     main_exit_err

wsa_ok:
    ; Save non-volatile registers
    mov     [rsp+608], rbx
    mov     [rsp+616], rbp
    mov     [rsp+624], r14
    mov     [rsp+576], r15

    ; 2. CreateIoCompletionPort
    xor     r9d, r9d
    xor     r8d, r8d
    xor     edx, edx
    mov     rcx, -1                ; INVALID_HANDLE_VALUE
    call    CreateIoCompletionPort
    mov     rbp, rax               ; rbp = CompletionPort
    test    rax, rax
    je      main_cleanup

    ; 3. GetSystemInfo
    lea     rcx, [rsp+88]          ; &SystemInfo
    call    GetSystemInfo

    ; Calculate thread count: SystemInfo.dwNumberOfProcessors * 2
    mov     ecx, dword ptr [rsp+88+32] ; dwNumberOfProcessors is at offset 32
    xor     r15d, r15d             ; loop index (i) = 0
    mov     ebx, r15d              ; target max threads
    add     ecx, ecx
    je      setup_socket
    mov     ebx, ecx

thread_loop:
    ; 4. CreateThread
    mov     qword ptr [rsp+40], 0
    lea     r8, ServerWorkerThread
    mov     r9, rbp                ; CompletionPort ID
    mov     dword ptr [rsp+32], 0
    xor     edx, edx
    xor     ecx, ecx               ; NULL Security
    call    CreateThread

    test    rax, rax
    je      thread_continue
    mov     rcx, rax
    call    CloseHandle            ; Close thread handle to prevent leak
thread_continue:
    inc     r15d
    cmp     r15d, ebx
    jb      thread_loop

setup_socket:
    ; 5. socket()
    mov     ecx, 2                 ; AF_INET
    mov     edx, 1                 ; SOCK_STREAM
    mov     r8d, 6                 ; IPPROTO_TCP
    call    socket
    mov     r14, rax               ; r14 = ListenSocket
    cmp     rax, -1
    je      main_cleanup

    ; 6. inet_addr()
    lea     rcx, str_ip
    mov     word ptr [rsp+72], 2   ; service.sin_family = AF_INET
    call    inet_addr

    ; 7. htons()
    mov     ecx, 8888
    mov     dword ptr [rsp+76], eax ; service.sin_addr.s_addr
    call    htons

    ; 8. bind()
    mov     r8d, 16                ; sizeof(sockaddr_in)
    lea     rdx, [rsp+72]          ; &service
    mov     rcx, r14               ; ListenSocket
    mov     word ptr [rsp+74], ax  ; service.sin_port
    call    bind
    cmp     eax, -1
    je      main_cleanup

    ; 9. listen()
    mov     edx, 2147483647        ; SOMAXCONN
    mov     rcx, r14
    call    listen
    cmp     eax, -1
    je      main_cleanup

    lea     rcx, str_iocp_run
    call    printf

accept_loop:
    ; 10. accept()
    xor     r8d, r8d
    xor     edx, edx
    mov     rcx, r14               ; ListenSocket
    call    accept
    mov     rdi, rax               ; rdi = AcceptSocket
    cmp     rax, -1
    je      accept_loop

    ; 11. CreateIoCompletionPort()
    xor     r9d, r9d
    mov     r8, rax                ; CompletionKey = AcceptSocket
    mov     rdx, rbp               ; CompletionPort
    mov     rcx, rax               ; AcceptSocket
    call    CreateIoCompletionPort

    ; 12. GlobalAlloc()
    mov     edx, 1080              ; sizeof(PER_IO_DATA) (1024 buffer + 48 IO Struct)
    mov     ecx, 64                ; GPTR (GMEM_FIXED | GMEM_ZEROINIT)
    call    GlobalAlloc
    mov     rsi, rax               ; rsi = PerIoData

    test    rax, rax
    jne     init_io

    ; Alloc failed, cleanup socket
    mov     rcx, rdi
    call    closesocket
    jmp     accept_loop

init_io:
    mov     qword ptr [rsi+1072], rdi ; PerIoData->Socket = AcceptSocket

    ; Set up DataBuf structure inside PerIoData
    lea     rax, [rsi+48]          ; Address of PerIoData->Buffer
    mov     dword ptr [rsi+32], 1024 ; PerIoData->DataBuf.len = 1024
    mov     qword ptr [rsi+40], rax  ; PerIoData->DataBuf.buf = rax

    ; 13. send() welcome message
    lea     rdx, str_welcome
    xor     r9d, r9d               ; Flags = 0
    mov     r8d, 25                ; strlen("Welcome to Oscar server!\n")
    mov     rcx, rdi               ; AcceptSocket
    call    send

    ; 14. WSARecv()
    lea     rax, [rsp+64]          ; &Flags variable on stack
    mov     qword ptr [rsp+48], 0  ; NULL Routine
    mov     qword ptr [rsp+40], rsi  ; PerIoData pointer (&Overlapped)
    lea     r9, [rsp+68]           ; &RecvBytes
    mov     r8d, 1                 ; dwBufferCount
    mov     qword ptr [rsp+32], rax  ; lpFlags
    lea     rdx, [rsi+32]          ; &PerIoData->DataBuf
    mov     dword ptr [rsp+68], 0  ; Initialize RecvBytes to 0
    mov     rcx, rdi               ; AcceptSocket
    mov     dword ptr [rsp+64], 0  ; Initialize Flags to 0
    call    WSARecv

    cmp     eax, -1
    jne     accept_success

    call    WSAGetLastError
    cmp     eax, 997               ; WSA_IO_PENDING
    je      accept_success

    lea     rcx, str_initial_fail
    call    printf

accept_success:
    mov     rdx, rdi
    lea     rcx, str_new_client
    call    printf
    jmp     accept_loop            ; Infinite loop

main_cleanup:
    ; Restore non-volatile registers
    mov     r14, [rsp+624]
    mov     rbp, [rsp+616]
    mov     rbx, [rsp+608]
    mov     r15, [rsp+576]

main_exit_err:
    ; --- Epilogue ---
    call    WSACleanup
    mov     eax, 1                 ; Return 1
    add     rsp, 584
    pop     rdi
    pop     rsi
    ret
main ENDP
END
