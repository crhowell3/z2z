#ifndef CLIENTTHREAD_H
#define CLIENTTHREAD_H

#include <QThread>
#include <QMutex>
#include "ui_mainwindow.h"

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

  public slots:
    void clientMain();

  signals:
    void finished();
    void clientUpdated(const QString& message);

  protected:
    void run() override;

  private:
    QMutex mutex;
};

#endif  // CLIENTTHREAD_H