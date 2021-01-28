#include <QtCore>
#include <QApplication>
#include <QCommandLineOption>
#include <QCommandLineParser>
#include <QDebug>

#include "mainwindow.h"
#include "Client.h"
#include "Server.h"

int main(int argc, char* argv[])
{
    QApplication a(argc, argv);
    MainWindow w;
    w.show();

    auto client = new Client();
    client->ClientMain();

    return a.exec();
}