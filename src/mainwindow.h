#ifndef MAINWINDOW_H
#define MAINWINDOW_H

#include <QWidget>

namespace Ui {
class MainWindow;
}

class MainWindow : public QWidget
{
    Q_OBJECT

  public:
    MainWindow(QWidget* parent = nullptr);
};
#endif  // MAINWINDOW_H