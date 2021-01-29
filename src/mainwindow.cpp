#include "mainwindow.h"
#include "ui_mainwindow.h"

#include <QApplication>
#include <QScreen>
#include <QMenuBar>
#include <QMessageBox>
#include <iostream>
#include <QThread>

#include "Client.h"
#include "ServerThread.h"

MainWindow::MainWindow(QWidget* parent)
  : QWidget(parent)
{
    Ui::MainWindow ui;
    auto server = new ServerThread();
    connect(ui.serverButton, &QPushButton::clicked, [server]() {
        auto thread = new QThread;
        server->moveToThread(thread);
        thread->start();
        if (thread->isRunning())
        {
            server->ServerMain();
            thread->quit();
        }
    });
}