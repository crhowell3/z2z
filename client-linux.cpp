#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netdb.h>
#include <string>
#include <iostream>
#include <errno.h>
#include <arpa/inet.h>
#include <sys/wait.h>
#include <signal.h>
#include <map>
#include <sstream>
#include <thread>

#define DEFAULT_BUFLEN 512
#define DEFAULT_PORT "27015"

// (TODO) Convert this code to be compatible with Linux sockets

struct client_type
{
    SOCKET socket;
    int id;
    char received_message[DEFAULT_BUFLEN];
};

int process_client(client_type &new_client);
int main(int argc, char **argv);

int process_client(client_type &new_client)
{
    while (1)
    {
        memset(new_client.received_message, 0, DEFAULT_BUFLEN);

        if (new_client.socket != 0)
        {
            int i_result = recv(new_client.socket, new_client.received_message, DEFAULT_BUFLEN, 0);

            if (i_result != SOCKET_ERROR)
            {
                std::cout << new_client.received_message << std::endl;
            }
            else
            {
                std::cout << "recv() failed: " << WSAGetLastError() << std::endl;
                break;
            }
        }
    }

    if (WSAGetLastError() == WSAECONNRESET)
    {
        std::cout << "The server has disconnected" << std::endl;
    }

    return 0;
}

int __cdecl main(int argc, char **argv)
{
    WSADATA wsa_data;
    struct addrinfo *result = NULL,
                    *ptr = NULL,
                    hints;
    std::string sent_message = "";
    client_type client = {INVALID_SOCKET, -1, ""};
    int i_result = 0;
    std::string message;

    // Validate the parameters
    if (argc != 2)
    {
        printf("usage: %s server-name\n", argv[0]);
        return 1;
    }

    std::cout << "Starting client...\n";

    // Initialize Winsock
    i_result = WSAStartup(MAKEWORD(2, 2), &wsa_data);
    if (i_result != 0)
    {
        std::cout << "WSAStartup failed with error: " << i_result << std::endl;
        return 1;
    }

    ZeroMemory(&hints, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_protocol = IPPROTO_TCP;

    std::cout << "Connecting...\n";

    // Resolve the server address and port
    i_result = getaddrinfo(argv[1], DEFAULT_PORT, &hints, &result);
    if (i_result != 0)
    {
        std::cout << "getaddrinfo failed with error: " << i_result << std::endl;
        WSACleanup();
        system("pause");
        return 1;
    }

    // Attempt to connect to an address until one succeeds
    for (ptr = result; ptr != NULL; ptr = ptr->ai_next)
    {
        // Create a SOCKET for connecting to the server
        client.socket = socket(ptr->ai_family, ptr->ai_socktype, ptr->ai_protocol);
        if (client.socket == INVALID_SOCKET)
        {
            std::cout << "socket() failed with error: " << WSAGetLastError() << std::endl;
            WSACleanup();
            system("pause");
            return 1;
        }

        // connect to server
        i_result = connect(client.socket, ptr->ai_addr, (int)ptr->ai_addrlen);
        if (i_result == SOCKET_ERROR)
        {
            closesocket(client.socket);
            client.socket = INVALID_SOCKET;
            continue;
        }
        break;
    }

    freeaddrinfo(result);

    if (client.socket == INVALID_SOCKET)
    {
        std::cout << "Unable to connect to server!" << std::endl;
        WSACleanup();
        system("pause");
        return 1;
    }

    std::cout << "Connected successfully" << std::endl;

    // Get id from server for this client
    recv(client.socket, client.received_message, DEFAULT_BUFLEN, 0);
    message = client.received_message;

    if (message != "Server is full")
    {
        client.id = atoi(client.received_message);

        std::thread client_thread(process_client, std::ref(client));

        while (1)
        {
            getline(std::cin, sent_message);
            i_result = send(client.socket, sent_message.c_str(), strlen(sent_message.c_str()), 0);

            if (i_result <= 0)
            {
                std::cout << "send() failed: " << WSAGetLastError() << std::endl;
                break;
            }
        }

        client_thread.detach();
    }
    else
    {
        std::cout << client.received_message << std::endl;
    }

    std::cout << "Shutting down socket..." << std::endl;
    i_result = shutdown(client.socket, SD_SEND);
    if (i_result == SOCKET_ERROR)
    {
        std::cout << "shutdown() failed with error: " << WSAGetLastError() << std::endl;
        closesocket(client.socket);
        WSACleanup();
        system("pause");
        return 1;
    }

    closesocket(client.socket);
    WSACleanup();
    system("pause");
    return 0;
}
