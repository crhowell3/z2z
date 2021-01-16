#undef UNICODE

#define WIN32_LEAN_AND_MEAN

#include <windows.h>
#include <winsock2.h>
#include <WS2tcpip.h>
#include <stdlib.h>
#include <stdio.h>

#pragma comment(lib, "Ws2_32.lib")

#define DEFAULT_BUFLEN 512
#define DEFAULT_PORT "7405"

int __cdecl main(void)
{
    WSADATA wsa_data;
    int i_result;

    SOCKET listen_socket = INVALID_SOCKET;
    SOCKET client_socket = INVALID_SOCKET;

    struct addrinfo *result = NULL;
    struct addrinfo hints;

    int i_send_result;
    char recvbuf[DEFAULT_BUFLEN];
    int recvbuflen = DEFAULT_BUFLEN;

    // Initialize winsock service
    i_result = WSAStartup(MAKEWORD(2, 2), &wsa_data);
    if (i_result != 0)
    {
        printf("WSAStartup failed: %d\n", i_result);
        return 1;
    }

    ZeroMemory(&hints, sizeof(hints));
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_protocol = IPPROTO_TCP;
    hints.ai_flags = AI_PASSIVE;

    // Resolve the server address and port
    i_result = getaddrinfo(NULL, DEFAULT_PORT, &hints, &result);
    if (i_result != 0)
    {
        printf("getaddressinfo failed with error: %d\n", i_result);
        WSACleanup();
        return 1;
    }

    // Create a SOCKET for connecting to server
    listen_socket = socket(result->ai_family, result->ai_socktype, result->ai_protocol);
    if (listen_socket == INVALID_SOCKET)
    {
        printf("socket failed with error: &d\n", WSAGetLastError());
        freeaddrinfo(result);
        WSACleanup();
        return 1;
    }

    // Setup the TCP listening socket
    i_result = bind(listen_socket, result->ai_addr, (int)result->ai_addrlen);
    if (i_result == SOCKET_ERROR)
    {
        printf("bind failed with error: %d\n", WSAGetLastError());
        freeaddrinfo(result);
        closesocket(listen_socket);
        WSACleanup();
        return 1;
    }

    freeaddrinfo(result);

    i_result = listen(listen_socket, SOMAXCONN);
    if (i_result == SOCKET_ERROR)
    {
        printf("listen failed with error: %d\n", WSAGetLastError());
        closesocket(listen_socket);
        WSACleanup();
        return 1;
    }

    // Accept a client socket
    client_socket = accept(listen_socket, NULL, NULL);
    if (client_socket == INVALID_SOCKET)
    {
        printf("accept failed with error: %d\n", WSAGetLastError());
        closesocket(listen_socket);
        WSACleanup();
        return 1;
    }

    closesocket(client_socket);

    // Receive until the peer shuts down the connection
    do
    {
        i_result = recv(client_socket, recvbuf, recvbuflen, 0);
        if (i_result > 0)
        {
            printf("Bytes received: %d\n", i_result);

            // Echo the buffer back to the sender
            i_send_result = send(client_socket, recvbuf, i_result, 0);
            if (i_send_result == SOCKET_ERROR)
            {
                printf("send failed with error: %d\n", WSAGetLastError());
                closesocket(client_socket);
                WSACleanup();
                return 1;
            }
            printf("Bytes sent: %d\n", i_send_result);
        }
        else if (i_result == 0)
        {
            printf("Connection closing...\n");
        }
        else
        {
            printf("recv failed with error: %d\n", WSAGetLastError());
            closesocket(client_socket);
            WSACleanup();
            return 1;
        }
    } while (i_result > 0);

    // Shutdown the connection because communication is complete
    i_result = shutdown(client_socket, SD_SEND);
    if (i_result == SOCKET_ERROR)
    {
        printf("Shutdown failed with error: %d\n", WSAGetLastError());
        closesocket(client_socket);
        WSACleanup();
        return 1;
    }

    // Cleanup
    closesocket(client_socket);
    WSACleanup();

    return 0;
}
