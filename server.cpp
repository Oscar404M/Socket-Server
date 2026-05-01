#define _WINSOCK_DEPRECATED_NO_WARNINGS
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif

#include <windows.h>
#include <winsock2.h>
#include <ws2tcpip.h>
#include <stdio.h>
#include <stdlib.h>

#pragma comment(lib, "Ws2_32.lib")

constexpr int DATA_BUFSIZE = 1024;

// Context structure to keep track of I/O operations
typedef struct {
    OVERLAPPED Overlapped;
    WSABUF DataBuf;
    CHAR Buffer[DATA_BUFSIZE];
    SOCKET Socket;
} PER_IO_DATA, * LPPER_IO_DATA;

// Worker Thread Function
DWORD WINAPI ServerWorkerThread(LPVOID CompletionPortID) {
    HANDLE CompletionPort = (HANDLE)CompletionPortID;
    DWORD BytesTransferred = 0;
    ULONG_PTR CompletionKey = 0;
    LPPER_IO_DATA PerIoData = NULL;
    DWORD Flags = 0;

    while (TRUE) {
        // Wait for an I/O operation to complete
        BOOL result = GetQueuedCompletionStatus(
            CompletionPort,
            &BytesTransferred,
            &CompletionKey,
            (LPOVERLAPPED*)&PerIoData,
            INFINITE
        );

        if (!result || BytesTransferred == 0) {
            if (PerIoData) {
                printf("Client disconnected on fd %llu\n", PerIoData->Socket);
                closesocket(PerIoData->Socket);
                GlobalFree(PerIoData);
            }
            continue;
        }

        // Echo the received data back to the client
        printf("Received from fd %llu: %s\n", PerIoData->Socket, PerIoData->Buffer);
        //send(PerIoData->Socket, PerIoData->Buffer, BytesTransferred, 0);

        // Prepare for the next read operation
        SecureZeroMemory(&(PerIoData->Overlapped), sizeof(OVERLAPPED));
        PerIoData->DataBuf.len = DATA_BUFSIZE;
        PerIoData->DataBuf.buf = PerIoData->Buffer;
        SecureZeroMemory(PerIoData->Buffer, DATA_BUFSIZE);

        Flags = 0;
        if (WSARecv(PerIoData->Socket, &(PerIoData->DataBuf), 1, &BytesTransferred, &Flags, &(PerIoData->Overlapped), NULL) == SOCKET_ERROR) {
            if (WSAGetLastError() != WSA_IO_PENDING) {
                printf("WSARecv failed with error %d\n", WSAGetLastError());
            }
        }
    }
    return 0;
}

int main() {
    WSADATA wsaData;
    if (WSAStartup(MAKEWORD(2, 2), &wsaData) != 0) {
        printf("WSAStartup failed.\n");
        return 1;
    }

    // 1. Create the Completion Port
    HANDLE CompletionPort = CreateIoCompletionPort(INVALID_HANDLE_VALUE, NULL, 0, 0);
    if (CompletionPort == NULL) return 1;

    // 2. Create Worker Threads based on CPU count
    SYSTEM_INFO SystemInfo;
    GetSystemInfo(&SystemInfo);
    for (DWORD i = 0; i < SystemInfo.dwNumberOfProcessors * 2; i++) {
        HANDLE ThreadHandle = CreateThread(NULL, 0, ServerWorkerThread, CompletionPort, 0, NULL);
        if (ThreadHandle) CloseHandle(ThreadHandle);
    }

    // 3. Setup the Listening Socket
    SOCKET Listen = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (Listen == INVALID_SOCKET) return 1;

    sockaddr_in service;
    service.sin_family = AF_INET;
    service.sin_addr.s_addr = inet_addr("127.0.0.1");
    service.sin_port = htons(8888);

    if (bind(Listen, (sockaddr*)&service, sizeof(service)) == SOCKET_ERROR) return 1;
    if (listen(Listen, SOMAXCONN) == SOCKET_ERROR) return 1;

    printf("IOCP Server running at 127.0.0.1:8888\n");

    while (TRUE) {
        // 4. Accept a new client
        SOCKET Accept = accept(Listen, NULL, NULL);
        if (Accept == INVALID_SOCKET) continue;

        // 5. Associate the socket with the Completion Port
        CreateIoCompletionPort((HANDLE)Accept, CompletionPort, (ULONG_PTR)Accept, 0);

        // 6. Initialize I/O data and post the first Receive request
        LPPER_IO_DATA PerIoData = (LPPER_IO_DATA)GlobalAlloc(GPTR, sizeof(PER_IO_DATA));
        if (PerIoData == NULL) {
            closesocket(Accept);
            continue;
        }

        PerIoData->Socket = Accept;
        PerIoData->DataBuf.buf = PerIoData->Buffer;
        PerIoData->DataBuf.len = DATA_BUFSIZE;

        const char* welcomeMsg = "Welcome to Oscar server!\n";
        send(Accept, welcomeMsg, (int)strlen(welcomeMsg), 0);

        DWORD RecvBytes = 0, Flags = 0;
        if (WSARecv(Accept, &(PerIoData->DataBuf), 1, &RecvBytes, &Flags, &(PerIoData->Overlapped), NULL) == SOCKET_ERROR) {
            if (WSAGetLastError() != WSA_IO_PENDING) {
                printf("Initial WSARecv failed.\n");
            }
        }

        printf("New client connected: fd %llu\n", Accept);
    }

    WSACleanup();
    return 0;
}
