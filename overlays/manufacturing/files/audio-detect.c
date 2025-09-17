#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <linux/input.h>
#include <unistd.h>

int main(int argc, char *argv[]) {
    int fd;
    struct input_event ev;
    int count = 0;

    if (argc == 1) {
        perror("No device provided. e.g. /dev/input/event3");
	return 1;
    }

    fd = open(argv[1], O_RDONLY);
    if (fd == -1) {
        perror("Error opening input device");
        return 1;
    }

    printf("Listening for events on %s...\n", argv[1]);

    while (1) {
        if (read(fd, &ev, sizeof(struct input_event)) < 0) {
            perror("Error reading event");
            close(fd);
            break;
        }

        printf("Type %d, Code %d, Value %d\n", ev.type, ev.code, ev.value);

        // We only need 3 events
        if (++count == 3)
            break;
    }

    close(fd);
    return 0;
}
