#ifndef CLIENTTHREAD_H
#define CLIENTTHREAD_H

#include <QThread>
#include <QMutex>
#include "ui_ClientWindow.h"

class ClientThread : public QThread
{
    Q_OBJECT
  public:
    //
    // Default constructor and destructor
    //
    ClientThread(QObject* parent = nullptr);
    ~ClientThread();
    /**
     * @brief Thread dispatcher and client handler
     * Handles the bulk of the client connection
     */
    void* ProcessClient(void* threadarg);
    /**
     * @brief 
     * 
     */
    void BeginThreadAbortion();

  public slots:
    void clientMain();

  signals:
    void finished();
    void clientUpdated(const QString& message);

  protected:
    void run() override;

  private:
    QMutex mutex;
    bool abort_ = false;
};

#endif  // CLIENTTHREAD_H