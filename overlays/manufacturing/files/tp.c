#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>
#include <linux/input.h>

int main(int argc, char *argv[]) {
    const char *device = argv[1];  // Replace with your device

    if (argc == 1) {
        perror("Not input device provided. e.g. /dev/input/event3");
        return -1;
    }

    int fd = open(device, O_RDONLY);
    if (fd == -1) {
        perror("Error opening device");
        return -1;
    }

    struct input_event ev;
    while (read(fd, &ev, sizeof(struct input_event)) > 0) {
        if (ev.type == EV_ABS) {
            if (ev.code == ABS_MT_POSITION_X) {
                printf("X: %d\n", ev.value);
            } else if (ev.code == ABS_MT_POSITION_Y) {
                printf("Y: %d\n", ev.value);
		return 0;
            }
        }
    }

    close(fd);
    return 1;
}
