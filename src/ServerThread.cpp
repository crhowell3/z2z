#undef UNICODE

#define WIN32_LEAN_AND_MEAN

#include <windows.h>
#include <WinSock2.h>
#include <WS2tcpip.h>
#include <stdlib.h>
#include <stdio.h>
#include <iostream>
#include <vector>
#include <pthread.h>
#include <string>
#include "ServerThread.h"
#include "ui_mainwindow.h"

#define DEFAULT_BUFLEN 512
#define DEFAULT_PORT "27015"

const char OPTION_VALUE = 1;
const int MAX_CLIENTS = 10;

typedef void* (*THREADFUNCPTR)(void*);

struct client_type
{
    int id;
    SOCKET socket;
};

struct thread_data
{
    int thread_id;
    client_type new_client;
    std::vector<client_type> client_array;
};

ServerThread::ServerThread(QObject* parent)
  : QThread(parent){};
ServerThread::~ServerThread()
{
    mutex.lock();
    abort = true;
    mutex.unlock();

    wait();
};

void* ServerThread::ProcessServer(void* threadarg)
{
    pthread_detach(pthread_self());
    struct thread_data* data;
    data = (struct thread_data*)threadarg;

    std::string msg = "";
    char tempmsg[DEFAULT_BUFLEN] = "";

    while (1)
    {
        memset(tempmsg, 0, DEFAULT_BUFLEN);

        if (data->new_client.socket != 0)
        {
            int i_result = recv(data->new_client.socket, tempmsg, DEFAULT_BUFLEN, 0);

            if (i_result != SOCKET_ERROR)
            {
                if (strcmp("", tempmsg))
                {
                    msg = "Client #" + std::to_string(data->new_client.id) + ": " + tempmsg;
                }

                std::cout << msg.c_str() << std::endl;

                for (int i = 0; i < MAX_CLIENTS; i++)
                {
                    if (data->client_array[i].socket != INVALID_SOCKET)
                    {
                        if (data->new_client.id != i)
                        {
                            i_result = send(data->client_array[i].socket, msg.c_str(), strlen(msg.c_str()), 0);
                        }
                    }
                }
            }
            else
            {
                msg = "Client #" + std::to_string(data->new_client.id) + " disconnected";

                ui->serverStatus->append(QString::fromUtf8(msg.c_str()));

                closesocket(data->new_client.socket);
                closesocket(data->client_array[data->new_client.id].socket);
                data->client_array[data->new_client.id].socket = INVALID_SOCKET;

                for (int i = 0; i < MAX_CLIENTS; i++)
                {
                    if (data->client_array[i].socket != INVALID_SOCKET)
                    {
                        i_result = send(data->client_array[i].socket, msg.c_str(), strlen(msg.c_str()), 0);
                    }
                }

                break;
            }
        }
    }

    pthread_exit(NULL);

    return 0;
}

void ServerThread::run()
{
    WSADATA wsa_data;

    SOCKET listen_socket = INVALID_SOCKET;

    struct addrinfo* result = NULL;
    struct addrinfo hints;

    std::string msg = "";
    std::vector<client_type> client(MAX_CLIENTS);
    int num_clients = 0;
    int temp_id = -1;

    pthread_t threads[MAX_CLIENTS];
    struct thread_data td[MAX_CLIENTS];

    // Initialize winsock service
    server_ui_->serverStatus->append("Initializing Winsock...");
    QApplication::processEvents();
    WSAStartup(MAKEWORD(2, 2), &wsa_data);

    // Setup hints
    ZeroMemory(&hints, sizeof(hints));
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_protocol = IPPROTO_TCP;
    hints.ai_flags = AI_PASSIVE;

    // Resolve the server address and port
    server_ui_->serverStatus->append("Setting up the server...");
    QApplication::processEvents();
    getaddrinfo(NULL, DEFAULT_PORT, &hints, &result);

    // Create a SOCKET for connecting to server
    server_ui_->serverStatus->append("Creating the server socket...");
    QApplication::processEvents();
    listen_socket = socket(result->ai_family, result->ai_socktype, result->ai_protocol);

    // Setup socket options
    setsockopt(listen_socket, SOL_SOCKET, SO_REUSEADDR, &OPTION_VALUE, sizeof(int));
    setsockopt(listen_socket, IPPROTO_TCP, TCP_NODELAY, &OPTION_VALUE, sizeof(int));

    // Setup the TCP listening socket
    server_ui_->serverStatus->append("Binding socket...");
    QApplication::processEvents();
    bind(listen_socket, result->ai_addr, (int)result->ai_addrlen);

    // Listen for incoming connections
    server_ui_->serverStatus->append("Listening...");
    QApplication::processEvents();
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
            std::string client_msg = "Client # " + std::to_string(client[temp_id].id) + " accepted";
            server_ui_->serverStatus->append(QString::fromUtf8(client_msg.c_str()));
            QApplication::processEvents();
            msg = std::to_string(client[temp_id].id);
            send(client[temp_id].socket, msg.c_str(), strlen(msg.c_str()), 0);

            td[temp_id].new_client = client[temp_id];
            td[temp_id].thread_id = client[temp_id].id;
            td[temp_id].client_array = client;

            // Create a thread process for that client
            int rc = pthread_create(&threads[temp_id], NULL, (THREADFUNCPTR)&ServerThread::ProcessServer, (void*)&td[temp_id]);
        }
        else
        {
            msg = "Server is full";
            send(incoming, msg.c_str(), strlen(msg.c_str()), 0);
            server_ui_->serverStatus->append(QString::fromUtf8(msg.c_str()));
            QApplication::processEvents();
        }
    }

    // Close the server's listening socket
    closesocket(listen_socket);

    // Close client sockets
    for (int i = 0; i < MAX_CLIENTS; i++)
    {
        pthread_join(threads[i], NULL);
        closesocket(client[i].socket);
    }

    // Cleanup
    WSACleanup();
    server_ui_->serverStatus->append("Server closed successfully");
    QApplication::processEvents();

    pthread_exit(NULL);
}