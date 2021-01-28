#ifndef SERVER_H
#define SERVER_H

class Server
{
  public:
    //
    // Default constructor and destructor
    //
    Server();
    ~Server();
    /**
     * @brief 
     * 
     */
    void ServerRun();
    /**
     * @brief 
     * 
     * @return int 
     */
    int ServerMain();
};

#endif  // SERVER_H