#ifndef SERVER_H
#define SERVER_H

#include "mainwindow.h"

class Server : public QObject
{
    Q_OBJECT
  public:
    //
    // Default constructor and destructor
    //
    explicit Server(Ui::MainWindow* ui);
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

    Ui::MainWindow* server_ui_;

  public slots:
    void ServerMain();
};

#endif  // SERVER_H