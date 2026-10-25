#ifndef RUNGUARD_H
#define RUNGUARD_H

#include <QLockFile>
#include <QString>

// Single instance guard backed by a lock file in the per-user app data
// directory.  Unlike shared memory/semaphores this works inside the snap,
// flatpak, MSIX and Mac App Store sandboxes and recovers from stale locks
// left behind by a crash.
class RunGuard
{

public:
    explicit RunGuard( const QString& key );
    ~RunGuard();

    bool isAnotherRunning();
    bool tryToRun();
    void release();

private:
    QLockFile lockFile;

    Q_DISABLE_COPY( RunGuard )
};

#endif // RUNGUARD_H
