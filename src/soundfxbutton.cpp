#include "soundfxbutton.h"
#include <QMouseEvent>

SoundFxButton::SoundFxButton(const QVariant &data, const QString &label) {
    setButtonData(data);
    setText(label);
}

void SoundFxButton::setButtonData(const QVariant &data)
{
    m_data = data;
}

void SoundFxButton::mouseReleaseEvent(QMouseEvent *event)
{
    if (event->button() == Qt::RightButton)
    {
        emit customContextMenuRequested(event->position().toPoint());
        return;
    }
    QAbstractButton::mouseReleaseEvent(event);
}


