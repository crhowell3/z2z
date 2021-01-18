#undef UNICODE

#define WIN32_LEAN_AND_MEAN

#include <windows.h>
#include <winsock2.h>
#include <WS2tcpip.h>
#include <stdlib.h>
#include <stdio.h>
#include <iostream>
#include <vector>
#include <thread>
#include <string>

#define DEFAULT_BUFLEN 512
#define DEFAULT_PORT "27015"

struct client_type
{
    int id;
    SOCKET socket;
};

const char OPTION_VALUE = 1;
const int MAX_CLIENTS = 10;

int process_client(client_type &new_client, std::vector<client_type> &client_array, std::thread &thread);
int main(void);

int process_client(client_type &new_client, std::vector<client_type> &client_array, std::thread &thread)
{
    std::string msg = "";
    char tempmsg[DEFAULT_BUFLEN] = "";

    while (1)
    {
        memset(tempmsg, 0, DEFAULT_BUFLEN);

        if (new_client.socket != 0)
        {
            int i_result = recv(new_client.socket, tempmsg, DEFAULT_BUFLEN, 0);

            if (i_result != SOCKET_ERROR)
            {
                if (strcmp("", tempmsg))
                {
                    msg = "Client #" + std::to_string(new_client.id) + ": " + tempmsg;
                }

                std::cout << msg.c_str() << std::endl;

                for (int i = 0; i < MAX_CLIENTS; i++)
                {
                    if (client_array[i].socket != INVALID_SOCKET)
                    {
                        if (new_client.id != i)
                        {
                            i_result = send(client_array[i].socket, msg.c_str(), strlen(msg.c_str()), 0);
                        }
                    }
                }
            }
            else
            {
                msg = "Client #" + std::to_string(new_client.id) + " disconnected";

                std::cout << msg << std::endl;

                closesocket(new_client.socket);
                closesocket(client_array[new_client.id].socket);
                client_array[new_client.id].socket = INVALID_SOCKET;

                for (int i = 0; i < MAX_CLIENTS; i++)
                {
                    if (client_array[i].socket != INVALID_SOCKET)
                    {
                        i_result = send(client_array[i].socket, msg.c_str(), strlen(msg.c_str()), 0);
                    }
                }

                break;
            }
        }
    }

    thread.detach();

    return 0;
}

int __cdecl main(void)
{
    WSADATA wsa_data;

    SOCKET listen_socket = INVALID_SOCKET;

    struct addrinfo *result = NULL;
    struct addrinfo hints;

    std::string msg = "";
    std::vector<client_type> client(MAX_CLIENTS);
    int num_clients = 0;
    int temp_id = -1;

    std::thread client_thread[MAX_CLIENTS];

    // Initialize winsock service
    std::cout << "Initializing Winsock..." << std::endl;
    WSAStartup(MAKEWORD(2, 2), &wsa_data);

    // Setup hints
    ZeroMemory(&hints, sizeof(hints));
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_protocol = IPPROTO_TCP;
    hints.ai_flags = AI_PASSIVE;

    // Resolve the server address and port
    std::cout << "Setting up the server..." << std::endl;
    getaddrinfo(NULL, DEFAULT_PORT, &hints, &result);

    // Create a SOCKET for connecting to server
    std::cout << "Creating the server socket..." << std::endl;
    listen_socket = socket(result->ai_family, result->ai_socktype, result->ai_protocol);

    // Setup socket options
    setsockopt(listen_socket, SOL_SOCKET, SO_REUSEADDR, &OPTION_VALUE, sizeof(int));
    setsockopt(listen_socket, IPPROTO_TCP, TCP_NODELAY, &OPTION_VALUE, sizeof(int));

    // Setup the TCP listening socket
    std::cout << "Binding socket..." << std::endl;
    bind(listen_socket, result->ai_addr, (int)result->ai_addrlen);

    // Listen for incoming connections
    std::cout << "Listening..." << std::endl;
    listen(listen_socket, SOMAXCONN);

    // Initialize the client list
    for (int i = 0; i < MAX_CLIENTS; i++)
    {
        client[i] = {-1, INVALID_SOCKET};
    }

    // Accept client sockets
    while (1)
    {
        SOCKET incoming = INVALID_SOCKET;
        incoming = accept(listen_socket, NULL, NULL);
        if (incoming == INVALID_SOCKET)
            continue;

        // Reset the number of clients
        num_clients = -1;

        // Create a temp id for next client
        temp_id = -1;
        for (int i = 0; i < MAX_CLIENTS; i++)
        {
            if (client[i].socket == INVALID_SOCKET && temp_id == -1)
            {
                client[i].socket = incoming;
                client[i].id = i;
                temp_id = i;
            }

            if (client[i].socket != INVALID_SOCKET)
                num_clients++;
        }

        if (temp_id != -1)
        {
            // Send the id to that client
            std::cout << "Client #" << client[temp_id].id << " accepted" << std::endl;
            msg = std::to_string(client[temp_id].id);
            send(client[temp_id].socket, msg.c_str(), strlen(msg.c_str()), 0);

            // Create a thread process for that client
            client_thread[temp_id] = std::thread(process_client, std::ref(client[temp_id]), std::ref(client), std::ref(client_thread[temp_id]));
        }
        else
        {
            msg = "Server is full";
            send(incoming, msg.c_str(), strlen(msg.c_str()), 0);
            std::cout << msg << std::endl;
        }
    }

    // Close the server's listening socket
    closesocket(listen_socket);

    // Close client sockets
    for (int i = 0; i < MAX_CLIENTS; i++)
    {
        client_thread[i].detach();
        closesocket(client[i].socket);
    }

    // Cleanup
    WSACleanup();
    std::cout << "Server closed successfully" << std::endl;

    system("pause");
    return 0;
}
