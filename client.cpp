#define WIN32_LEAN_AND_MEAN

#include <windows.h>
#include <WinSock2.h>
#include <WS2tcpip.h>
#include <stdlib.h>
#include <stdio.h>

// Linking with Ws2_32.lib, Mswsock.lib, and Advapi32.lib
#pragma comment(lib, "Ws2_32.lib")
#pragma comment(lib, "Mswsock.lib")
#pragma comment(lib, "Advapi32.lib")

#define DEFAULT_BUFLEN 512
#define DEFAULT_PORT "7405"

int __cdecl main(int argc, char **argv)
{
    WSADATA wsa_data;
    SOCKET connect_socket = INVALID_SOCKET;
    struct addrinfo *result = NULL,
                    *ptr = NULL,
                    hints;
    const char *sendbuf = "This is a test";
    char recvbuf[DEFAULT_BUFLEN];
    int i_result;
    int recvbuflen = DEFAULT_BUFLEN;

    // Validate the parameters
    if (argc != 2)
    {
        printf("usage: %s server-name\n", argv[0]);
        return 1;
    }

    ZeroMemory(&hints, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_protocol = IPPROTO_TCP;

    // Resolve the server address and port
    i_result = getaddrinfo(argv[1], DEFAULT_PORT, &hints, &result);
    if (i_result != 0)
    {
        printf("getaddrinfo failed with error: %d\n", i_result);
        WSACleanup();
        return 1;
    }

    // Attempt to connect to an address until one succeeds
    for (ptr = result; ptr != NULL; ptr = ptr->ai_next)
    {
        // Create a SOCKET for connecting to the server
        connect_socket = socket(ptr->ai_family, ptr->ai_socktype, ptr->ai_protocol);
        if (connect_socket == INVALID_SOCKET)
        {
            printf("Socket failed with error: %d\n", WSAGetLastError());
            WSACleanup();
            return 1;
        }

        // connect to server
        i_result = connect(connect_socket, ptr->ai_addr, (int)ptr->ai_addrlen);
        if (i_result == SOCKET_ERROR)
        {
            closesocket(connect_socket);
            connect_socket = INVALID_SOCKET;
            continue;
        }
        break;
    }

    freeaddrinfo(result);

    if (connect_socket == INVALID_SOCKET)
    {
        printf("Unable to connect to server!\n");
        WSACleanup();
        return 1;
    }

    // Send an initial buffer
    i_result = send(connect_socket, sendbuf, (int)strlen(sendbuf), 0);
    if (i_result == SOCKET_ERROR)
    {
        printf("Send failed with error: %d\n", WSAGetLastError());
        closesocket(connect_socket);
        WSACleanup();
        return 1;
    }

    printf("Bytes Sent: %d\n", i_result);

    // Shutdown the connection because no more data is being sent
    i_result = shutdown(connect_socket, SD_SEND);
    if (i_result == SOCKET_ERROR)
    {
        printf("Shutdown failed with error: %d\n", WSAGetLastError());
        closesocket(connect_socket);
        WSACleanup();
        return 1;
    }

    // Receive until the peer closes the connection
    do
    {
        i_result = recv(connect_socket, recvbuf, recvbuflen, 0);
        if (i_result > 0)
        {
            printf("Bytes received: %d\n", i_result);
        }
        else if (i_result == 0)
        {
            printf("Connection closed\n");
        }
        else
        {
            printf("recv failed with error: %d\n", WSAGetLastError());
        }
    } while (i_result > 0);

    // Cleanup
    closesocket(connect_socket);
    WSACleanup();

    return 0;
}