#include "runguard.h"

#include <QDir>
#include <QStandardPaths>

namespace
{

    QString lockFilePath( const QString& key )
    {
        QString dir = QStandardPaths::writableLocation( QStandardPaths::AppLocalDataLocation );
        if ( dir.isEmpty() )
            dir = QDir::tempPath();
        QDir().mkpath( dir );
        return dir + "/" + key + ".lock";
    }

}


RunGuard::RunGuard( const QString& key )
    : lockFile( lockFilePath( key ) )
{
    // Never treat a live lock as stale; stale locks from crashed processes
    // are detected by QLockFile via the stored pid.
    lockFile.setStaleLockTime( 0 );
}

RunGuard::~RunGuard()
{
    release();
}

bool RunGuard::isAnotherRunning()
{
    if ( lockFile.isLocked() )
        return false;

    if ( lockFile.tryLock() )
    {
        lockFile.unlock();
        return false;
    }
    return lockFile.error() == QLockFile::LockFailedError;
}

bool RunGuard::tryToRun()
{
    return lockFile.isLocked() || lockFile.tryLock();
}

void RunGuard::release()
{
    if ( lockFile.isLocked() )
        lockFile.unlock();
}
