#ifndef SERVER_H
#define SERVER_H

#include "mainwindow.h"

class Server
{
  public:
    //
    // Default constructor and destructor
    //
    Server(Ui::MainWindow* ui);
    ~Server();

    /**
     * @brief 
     * 
     * @param threadarg 
     * @return void* 
     */
    void* ProcessServer(void* threadarg);
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

    Ui::MainWindow* server_ui_;
};

#endif  // SERVER_H