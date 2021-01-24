# Homie Chat

## Running the Server

Compile `server.cpp` using `g++ -o server server.cpp -LC:\Windows\System32 -lws2_32`. Run the executable using `./server` or `./server.exe`. Make sure that your firewall will allow the program to execute. Note: The server **MUST** be started before the client code in order to work properly.

## Running the Client

Compile `client.cpp` using `g++ -o client client.cpp -LC:\Windows\System32 -lws2_32 -lmswsock -ladvapi32`. Run the executable using `./client <ip-addr>` or `./client.exe <ip-addr>`. If the server is running on the same machine as the client, use `localhost`. Otherwise, specify the IP address of the machine on which the server is running.

## Contributors

@crhowell3 - developer
@burkob66 - tester
