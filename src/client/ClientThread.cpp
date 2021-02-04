#define WIN32_LEAN_AND_MEAN

#include <windows.h>
#include <WinSock2.h>
#include <WS2tcpip.h>
#include <array>
#include <iostream>
#include <pthread.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include "ClientThread.h"

#define DEFAULT_BUFLEN 512
#define DEFAULT_PORT "27015"
#define NUM_THREADS 1
#define IP_ADDR "50.81.219.52"

using THREADFUNCPTR = void* (*)(void*);

struct client_type
{
    SOCKET socket;
    int id;
    std::array<char, DEFAULT_BUFLEN> received_message;
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
    auto* data = static_cast<struct thread_data*>(threadarg);
    while (true)
    {
        std::memset(data->new_client.received_message.data(), 0, DEFAULT_BUFLEN);

        if (data->new_client.socket != 0)
        {
            int i_result = recv(data->new_client.socket, data->new_client.received_message.data(), DEFAULT_BUFLEN, 0);

            if (i_result != SOCKET_ERROR)
            {
                std::cout << data->new_client.received_message.data() << std::endl;
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
    return nullptr;
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
    struct addrinfo* result = nullptr;
    struct addrinfo* ptr = nullptr;
    struct addrinfo hints
    {};
    std::string sent_message = "";
    client_type client = {INVALID_SOCKET, -1, {""}};
    int i_result = 0;
    std::string message;

    emit clientUpdated("Starting client...");
    QApplication::processEvents();

    // Initialize Winsock
    i_result = WSAStartup(MAKEWORD(2, 2), &wsa_data);
    if (i_result != 0)
    {
        std::string msg = &"WSAStartup failed with error: "[i_result];
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
        return;
    }

    // Attempt to connect to an address until one succeeds
    for (ptr = result; ptr != nullptr; ptr = ptr->ai_next)
    {
        if (!abort_)
        {
            // Create a SOCKET for connecting to the server
            client.socket = socket(ptr->ai_family, ptr->ai_socktype, ptr->ai_protocol);
            if (client.socket == INVALID_SOCKET)
            {
                std::cout << "socket() failed with error: " << WSAGetLastError() << std::endl;
                WSACleanup();
                return;
            }

            // connect to server
            i_result = ::connect(client.socket, ptr->ai_addr, static_cast<int>(ptr->ai_addrlen));
            if (i_result == SOCKET_ERROR)
            {
                closesocket(client.socket);
                client.socket = INVALID_SOCKET;
                continue;
            }
            break;
        }

        closesocket(client.socket);
        WSACleanup();
        emit finished();
        return;
    }

    freeaddrinfo(result);

    if (client.socket == INVALID_SOCKET)
    {
        std::cout << "Unable to connect to server!" << std::endl;
        WSACleanup();
        return;
    }

    emit clientUpdated("Connected successfully");
    QApplication::processEvents();

    // Get id from server for this client
    recv(client.socket, client.received_message.data(), DEFAULT_BUFLEN, 0);
    message = client.received_message.data();

    if (message != "Server is full")
    {
        client.id = atoi(client.received_message.data());

        td[0].thread_id = 0;
        td[0].new_client = client;

        // (TODO) Change std::thread to pthread
        rc = pthread_create(&threads[0], nullptr, (THREADFUNCPTR)&ClientThread::ProcessClient, (void*)&td[0]);

        if (rc != 0)
        {
            std::cout << "Thread did not complete successfully" << std::endl;
        }

        while (true)
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
        //std::cout << client.received_message << std::endl;
    }

    pthread_join(threads[0], NULL);

    emit clientUpdated("Shutting down socket...");
    i_result = shutdown(client.socket, SD_SEND);
    if (i_result == SOCKET_ERROR)
    {
        std::cout << "shutdown() failed with error: " << WSAGetLastError() << std::endl;
        closesocket(client.socket);
        WSACleanup();
        return;
    }

    closesocket(client.socket);
    WSACleanup();

    pthread_exit(nullptr);
}

void ClientThread::clientMain()
{
    run();
    emit finished();
}