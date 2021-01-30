#include <QtCore>
#include <QApplication>
#include <QCommandLineOption>
#include <QCommandLineParser>
#include <QDebug>
#include <QScreen>
#include <QMenuBar>
#include <QMessageBox>
#include <iostream>
#include <QThread>
#include <QWidget>
#include "ServerThread.h"
#include "ui_mainwindow.h"

Ui::MainWindow ui;

void updateUi(const QString& message)
{
    ui.serverStatus->append(message);
}

int main(int argc, char* argv[])
{
    QApplication app(argc, argv);
    QWidget* widget = new QWidget;
    ui.setupUi(widget);

    ServerThread server;
    QObject::connect(&server, &ServerThread::serverUpdated, updateUi);
    QObject::connect(ui.serverButton, &QPushButton::clicked, [&server]() {
        auto thread = new QThread;
        server.moveToThread(thread);
        thread->start();
        if (thread->isRunning())
        {
            server.ServerMain();
            thread->exit();
        }
    });

    widget->show();
    return app.exec();
}