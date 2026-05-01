option casemap:none
INCLUDELIB kernel32.lib
INCLUDELIB ws2_32.lib
INCLUDELIB msvcrt.lib
INCLUDELIB ucrt.lib
INCLUDELIB legacy_stdio_definitions.lib

; ==============================================================================
; EXTERNAL FUNCTIONS
; ==============================================================================

EXTRN WSAStartup:PROC
EXTRN WSACleanup:PROC
EXTRN WSARecv:PROC
EXTRN WSAGetLastError:PROC
EXTRN socket:PROC
EXTRN closesocket:PROC
EXTRN bind:PROC
EXTRN listen:PROC
EXTRN accept:PROC
EXTRN send:PROC
EXTRN inet_addr:PROC
EXTRN htons:PROC

EXTRN CreateIoCompletionPort:PROC
EXTRN GetQueuedCompletionStatus:PROC
EXTRN GetSystemInfo:PROC
EXTRN CreateThread:PROC
EXTRN CloseHandle:PROC
EXTRN GlobalAlloc:PROC
EXTRN GlobalFree:PROC

EXTRN printf:PROC
