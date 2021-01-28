#include "mainwindow.h"
#include "ui_mainwindow.h"

#include <QApplication>
#include <QScreen>
#include <QMenuBar>
#include <QMessageBox>
#include <QtConcurrent/QtConcurrent>
#include <iostream>

#include "Client.h"
#include "Server.h"

MainWindow::MainWindow(QWidget* parent)
  : QMainWindow(parent)
  , ui(new Ui::MainWindow)
{
    ui->setupUi(this);
    auto server = new Server(ui);
    connect(ui->serverButton, &QPushButton::clicked, server, &Server::ServerMain);
}

MainWindow::~MainWindow()
{
    delete ui;
}

void MainWindow::on_actionExit_triggered()
{
    this->close();
}