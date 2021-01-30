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

int main(int argc, char* argv[])
{
    QApplication app(argc, argv);
    QWidget* widget = new QWidget;
    Ui::MainWindow ui;
    ui.setupUi(widget);

    auto server = new ServerThread();
    QObject::connect(ui.serverButton, &QPushButton::clicked, [server]() {
        auto thread = new QThread;
        server->moveToThread(thread);
        thread->start();
        if (thread->isRunning())
        {
            server->ServerMain();
            if (thread->isFinished())
            {
                thread->exit();
            }
        }
    });

    widget->show();
    return app.exec();
}