#ifndef SERVERTHREAD_H
#define SERVERTHREAD_H

#include <QThread>
#include <QMutex>
#include <QWaitCondition>
#include "ui_ServerWindow.h"

class ServerThread : public QThread
{
    Q_OBJECT
  public:
    //
    // Default constructor and destructor
    //
    ServerThread(QObject* parent = nullptr);
    ~ServerThread() override;

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
    void BeginThreadAbortion();

  public slots:
    void serverMain();

  signals:
    void finished();
    void serverUpdated(const QString& message);

  protected:
    void run() override;

  private:
    QMutex mutex;
    QWaitCondition condition;
    bool abort_ = false;
};

#endif  // SERVERTHREAD_H