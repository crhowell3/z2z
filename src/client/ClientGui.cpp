#include <QtCore>
#include <QApplication>
#include <QCommandLineOption>
#include <QCommandLineParser>
#include <QDebug>
#include <QMenuBar>
#include <QMessageBox>
#include <QObject>
#include <QScreen>
#include <QThread>
#include <QWidget>
#include <iostream>
#include "ClientThread.h"
#include "ui_ClientWindow.h"

Ui::ClientWindow ui;

void updateUi(const QString& message)
{
    ui.clientStatus->append(message);
}

int main(int argc, char* argv[])
{
    QApplication app(argc, argv);
    std::unique_ptr<QWidget> widget = std::make_unique<QWidget>();
    ui.setupUi(widget.get());

    // Set clientDisconnect to disabled initially
    ui.clientDisconnect->setEnabled(false);

    // Setup client thread
    std::unique_ptr<QThread> thread = std::make_unique<QThread>();

    // Create a client worker object
    ClientThread client;

    // Move the client process to the QThread
    client.moveToThread(thread.get());

    // Connect signals and slots
    QObject::connect(thread.get(), &QThread::started, &client, &ClientThread::clientMain);
    QObject::connect(&client, &ClientThread::finished, thread.get(), &QThread::quit);
    QObject::connect(&client, &ClientThread::finished, &client, &ClientThread::deleteLater);
    QObject::connect(thread.get(), &QThread::finished, thread.get(), &QThread::deleteLater);
    QObject::connect(&client, &ClientThread::clientUpdated, updateUi);
    QObject::connect(ui.clientConnect, &QPushButton::clicked, [&thread]() {
        thread->start();
        QApplication::processEvents();
        ui.clientConnect->setEnabled(false);
        ui.clientDisconnect->setEnabled(true);
    });
    QObject::connect(ui.clientDisconnect, &QPushButton::clicked, [&client, &thread]() {
        ui.clientStatus->append("Disconnecting from server...");
        client.BeginThreadAbortion();
        if (thread->wait(2000))
        {
            thread->terminate();
            thread->wait();
        }
        ui.clientStatus->append("Disconnected.");
        ui.clientConnect->setEnabled(true);
        ui.clientDisconnect->setEnabled(false);
    });

    widget->show();
    return app.exec();
}