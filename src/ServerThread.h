#ifndef SERVER_H
#define SERVER_H

#include <QThread>
#include <QMutex>
#include <QWaitCondition>
#include "mainwindow.h"

class ServerThread : public QThread
{
    Q_OBJECT
  public:
    //
    // Default constructor and destructor
    //
    ServerThread(QObject* parent = nullptr);
    ~ServerThread();

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

  public slots:
    void ServerMain();

  protected:
    void run() override;

  private:
    QMutex mutex;
    QWaitCondition condition;
    bool abort = false;
};

#endif  // SERVER_H