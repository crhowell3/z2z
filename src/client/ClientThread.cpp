#define WIN32_LEAN_AND_MEAN

#include <windows.h>
#include <WinSock2.h>
#include <WS2tcpip.h>
#include <iostream>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string>
#include "ClientThread.h"

#define DEFAULT_BUFLEN 512
#define DEFAULT_PORT "27015"
#define NUM_THREADS 1
#define IP_ADDR "50.81.219.52"

typedef void* (*THREADFUNCPTR)(void*);

struct client_type
{
    SOCKET socket;
    int id;
    char received_message[DEFAULT_BUFLEN];
};

struct thread_data
{
    int thread_id;
    client_type new_client;
};

ClientThread::ClientThread(QObject* parent)
  : QThread(parent){};
ClientThread::~ClientThread()
{
    mutex.lock();
    abort_ = true;
    mutex.unlock();

    wait();
};

void* ClientThread::ProcessClient(void* threadarg)
{
    pthread_detach(pthread_self());
    struct thread_data* data;
    data = (struct thread_data*)threadarg;
    while (1)
    {
        memset(data->new_client.received_message, 0, DEFAULT_BUFLEN);

        if (data->new_client.socket != 0)
        {
            int i_result = recv(data->new_client.socket, data->new_client.received_message, DEFAULT_BUFLEN, 0);

            if (i_result != SOCKET_ERROR)
            {
                std::cout << data->new_client.received_message << std::endl;
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

    pthread_exit(NULL);
    return 0;
}

void ClientThread::BeginThreadAbortion()
{
    mutex.lock();
    abort_ = true;
    mutex.unlock();

    wait();
}

void ClientThread::run()
{
    // Thread arrays
    pthread_t threads[NUM_THREADS];
    struct thread_data td[NUM_THREADS];
    int rc;

    WSADATA wsa_data;
    struct addrinfo *result = NULL,
                    *ptr = NULL,
                    hints;
    std::string sent_message = "";
    client_type client = {INVALID_SOCKET, -1, ""};
    int i_result = 0;
    std::string message;

    emit clientUpdated("Starting client...");
    QApplication::processEvents();

    // Initialize Winsock
    i_result = WSAStartup(MAKEWORD(2, 2), &wsa_data);
    if (i_result != 0)
    {
        std::string msg = "WSAStartup failed with error: " + i_result;
        emit clientUpdated(QString::fromUtf8(msg.c_str()));
        return;
    }

    ZeroMemory(&hints, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_protocol = IPPROTO_TCP;

    emit clientUpdated("Connecting...");
    QApplication::processEvents();

    // Resolve the server address and port
    i_result = getaddrinfo(IP_ADDR, DEFAULT_PORT, &hints, &result);
    if (i_result != 0)
    {
        std::cout << "getaddrinfo failed with error: " << i_result << std::endl;
        WSACleanup();
        system("pause");
        return;
    }

    // Attempt to connect to an address until one succeeds
    for (ptr = result; ptr != NULL; ptr = ptr->ai_next)
    {
        if (!abort_)
        {
            // Create a SOCKET for connecting to the server
            client.socket = socket(ptr->ai_family, ptr->ai_socktype, ptr->ai_protocol);
            if (client.socket == INVALID_SOCKET)
            {
                std::cout << "socket() failed with error: " << WSAGetLastError() << std::endl;
                WSACleanup();
                system("pause");
                return;
            }

            // connect to server
            i_result = ::connect(client.socket, ptr->ai_addr, (int)ptr->ai_addrlen);
            if (i_result == SOCKET_ERROR)
            {
                closesocket(client.socket);
                client.socket = INVALID_SOCKET;
                continue;
            }
            break;
        }
        else
        {
            closesocket(client.socket);
            WSACleanup();
            emit finished();
            return;
        }
    }

    freeaddrinfo(result);

    if (client.socket == INVALID_SOCKET)
    {
        std::cout << "Unable to connect to server!" << std::endl;
        WSACleanup();
        system("pause");
        return;
    }

    emit clientUpdated("Connected successfully");
    QApplication::processEvents();

    // Get id from server for this client
    recv(client.socket, client.received_message, DEFAULT_BUFLEN, 0);
    message = client.received_message;

    if (message != "Server is full")
    {
        client.id = atoi(client.received_message);

        td[0].thread_id = 0;
        td[0].new_client = client;

        // (TODO) Change std::thread to pthread
        rc = pthread_create(&threads[0], NULL, (THREADFUNCPTR)&ClientThread::ProcessClient, (void*)&td[0]);

        if (rc != 0)
        {
            std::cout << "Thread did not complete successfully" << std::endl;
        }

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
    }
    else
    {
        std::cout << client.received_message << std::endl;
    }

    pthread_join(threads[0], NULL);

    emit clientUpdated("Shutting down socket...");
    i_result = shutdown(client.socket, SD_SEND);
    if (i_result == SOCKET_ERROR)
    {
        std::cout << "shutdown() failed with error: " << WSAGetLastError() << std::endl;
        closesocket(client.socket);
        WSACleanup();
        system("pause");
        return;
    }

    closesocket(client.socket);
    WSACleanup();

    pthread_exit(NULL);
}

void ClientThread::clientMain()
{
    run();
    emit finished();
}