#ifndef GEN1_OTA_NET_H
#define GEN1_OTA_NET_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Download URL into memory buffer (caller frees *out). Returns 0 on success. */
int ota_net_download_buffer(const char *url, long timeout_ms, char **out, size_t *out_len,
                            char *err, size_t err_len);

/* Download URL to a filesystem path. Returns 0 on success. */
int ota_net_download_file(const char *url, const char *path, long timeout_ms, char *err,
                          size_t err_len);

#ifdef __cplusplus
}
#endif

#endif
