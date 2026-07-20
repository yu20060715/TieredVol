#ifndef SETUP_DISCOVER_H
#define SETUP_DISCOVER_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>

#ifndef MAX_DISKS
#define MAX_DISKS 16
#endif

typedef struct {
    char name[32];
    char tran[16];
    int is_root;
    int is_mounted;
} disk_info_t;

long long sysfs_size_gb(const char *disk);
void sysfs_model(const char *disk, char *out, size_t len);
int load_all_disk_info(disk_info_t *out, int max);
void find_mount_for_disk(const char *disk, char *mp, size_t mp_size);
int cmd_list(void);

#endif
