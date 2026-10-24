#include <sys/file.h>

int cs2mac_flock(int fd, int operation) {
    return flock(fd, operation);
}
