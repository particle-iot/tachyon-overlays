#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <linux/i2c-dev.h>
#include <time.h>

// Configuration
#define I2C_BUS 2
#define MUX_ADDR 0x77
#define VREF 3.300f
#define SAMPLES 3
#define SLEEP_MS 0

// Default ADC addresses
const uint8_t default_addr_list[] = {0x4a, 0x48, 0x4b, 0x49};
const int default_addr_count = 4;

// Function prototypes
int select_mux_channel(int file, uint8_t channel);
uint8_t encode_channel_bits(uint8_t ch);
int read_channel_avg(int file, uint8_t addr, uint8_t ch, float *voltage);
void print_usage(const char *prog_name);

int main(int argc, char *argv[]) {
    struct timespec start_time, end_time;
    clock_gettime(CLOCK_MONOTONIC, &start_time);

    // Parse parameters
    uint8_t mux_channel = 0;
    uint8_t single_addr = 0;
    int use_single_addr = 0;

    if (argc > 1) {
        mux_channel = (uint8_t)atoi(argv[1]);
        if (mux_channel > 3) {
            print_usage(argv[0]);
            return 1;
        }
    }

    if (argc > 2) {
        single_addr = (uint8_t)strtol(argv[2], NULL, 16);
        use_single_addr = 1;
    }

    // Open I2C bus
    char filename[20];
    snprintf(filename, sizeof(filename), "/dev/i2c-%d", I2C_BUS);
    int file = open(filename, O_RDWR);
    if (file < 0) {
        perror("Failed to open I2C bus");
        return 1;
    }

    // Select MUX channel
    if (select_mux_channel(file, mux_channel) < 0) {
        close(file);
        return 1;
    }

    printf("=== Reading ADS7828 on PCA9544A channel %d ===\n", mux_channel);

    // Process ADC addresses
    const uint8_t *addr_list;
    int addr_count;

    if (use_single_addr) {
        addr_list = &single_addr;
        addr_count = 1;
    } else {
        addr_list = default_addr_list;
        addr_count = default_addr_count;
    }

    for (int i = 0; i < addr_count; i++) {
        uint8_t addr = addr_list[i];
        printf("\n--- Reading from ADC address: 0x%02x ---\n", addr);

        for (uint8_t ch = 0; ch < 8; ch++) {
            float voltage;
            if (read_channel_avg(file, addr, ch, &voltage) == 0) {
                printf("  Channel %d: Voltage=%.4f V\n", ch, voltage);
            } else {
                printf("  Channel %d: Read failed\n", ch);
            }
        }
    }

    close(file);

    // Calculate and print total time
    clock_gettime(CLOCK_MONOTONIC, &end_time);
    double total_time = (end_time.tv_sec - start_time.tv_sec) + 
                       (end_time.tv_nsec - start_time.tv_nsec) / 1e9;
    printf("\nTotal time: %.3f seconds\n", total_time);

    return 0;
}

int select_mux_channel(int file, uint8_t channel) {
    uint8_t mux_cmd = (uint8_t)(0x04 | channel);
    if (ioctl(file, I2C_SLAVE, MUX_ADDR) < 0) {
        perror("Failed to select MUX");
        return -1;
    }

    if (write(file, &mux_cmd, 1) != 1) {
        perror("Failed to set MUX channel");
        return -1;
    }

    if (SLEEP_MS > 0) {
        usleep(SLEEP_MS * 1000);
    }

    return 0;
}

uint8_t encode_channel_bits(uint8_t ch) {
    return (uint8_t)(((ch >> 1) | ((ch & 1) << 2)) & 0x07);
}

int read_channel_avg(int file, uint8_t addr, uint8_t ch, float *voltage) {
    uint8_t csel = encode_channel_bits(ch);
    uint8_t ctrl_byte = (uint8_t)(0x80 | (csel << 4) | 0x04);
    uint16_t sum = 0;
    int valid = 0;

    if (ioctl(file, I2C_SLAVE, addr) < 0) {
        perror("Failed to select ADC");
        return -1;
    }

    for (int i = 0; i < SAMPLES; i++) {
        if (write(file, &ctrl_byte, 1) != 1) {
            continue;
        }

        if (SLEEP_MS > 0) {
            usleep(SLEEP_MS * 1000);
        }

        uint8_t buf[2];
        if (read(file, buf, 2) == 2) {
            uint16_t raw = (uint16_t)(((buf[0] & 0x0F) << 8) | buf[1]);
            sum += raw;
            valid++;
        }

        if (SLEEP_MS > 0) {
            usleep(SLEEP_MS * 1000);
        }
    }

    if (valid == 0) {
        return -1;
    }

    uint16_t avg = sum / valid;
    *voltage = avg * VREF / 4096.0f;
    return 0;
}

void print_usage(const char *prog_name) {
    printf("Usage: %s [MUX_CHANNEL] [ADC_ADDR]\n", prog_name);
    printf("MUX_CHANNEL must be 0~3 (default: 0)\n");
    printf("ADC_ADDR must be hex value (e.g., 0x48)\n");
}
