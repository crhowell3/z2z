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
#include "ServerThread.h"
#include "ui_mainwindow.h"

Ui::MainWindow ui;

void updateUiFromServer(const QString& message)
{
    ui.serverStatus->append(message);
}

void updateUiFromClient(const QString& message)
{
    ui.clientStatus->append(message);
}

int main(int argc, char* argv[])
{
    QApplication app(argc, argv);
    QWidget* widget = new QWidget;
    ui.setupUi(widget);

    // Setup server thread
    auto server_thread = new QThread;

    // Setup server object
    ServerThread server;

    // Move the server process to a QThread
    server.moveToThread(server_thread);

    // Connect signals and slots
    QObject::connect(server_thread, &QThread::started, &server, &ServerThread::serverMain);
    QObject::connect(&server, &ServerThread::finished, server_thread, &QThread::quit);
    QObject::connect(&server, &ServerThread::finished, &server, &ServerThread::deleteLater);
    QObject::connect(server_thread, &QThread::finished, server_thread, &QThread::deleteLater);
    QObject::connect(&server, &ServerThread::serverUpdated, updateUiFromServer);
    QObject::connect(ui.serverButton, &QPushButton::clicked, [&server_thread]() {
        server_thread->start();
    });

    // Setup client thread
    auto thread = new QThread;

    // Create a client worker object
    ClientThread client;

    // Move the client process to the QThread
    client.moveToThread(thread);

    // Connect signals and slots
    QObject::connect(thread, &QThread::started, &client, &ClientThread::clientMain);
    QObject::connect(&client, &ClientThread::finished, thread, &QThread::quit);
    QObject::connect(&client, &ClientThread::finished, &client, &ClientThread::deleteLater);
    QObject::connect(thread, &QThread::finished, thread, &QThread::deleteLater);
    QObject::connect(&client, &ClientThread::clientUpdated, updateUiFromClient);
    QObject::connect(ui.clientButton, &QPushButton::clicked, [&thread]() {
        thread->start();
    });

    widget->show();
    return app.exec();
}