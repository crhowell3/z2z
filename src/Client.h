#ifndef CLIENT_H
#define CLIENT_H

class Client
{
  public:
    //
    // Default constructor and destructor
    //
    Client();
    ~Client();
    /**
     * @brief Thread dispatcher and client handler
     * Handles the bulk of the client connection
     */
    void ClientRun();
    /**
     * @brief "Main" method for a client object
     * Driver method for the client object
     * @return int 0 if completed successfully
     */
    int ClientMain();
};

#endif  // CLIENT_H