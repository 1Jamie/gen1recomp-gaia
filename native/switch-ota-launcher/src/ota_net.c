#include "ota_net.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(__SWITCH__)
#include <curl/curl.h>
#include <switch.h>
#endif

#if defined(__SWITCH__)
struct mem_buf {
  char *data;
  size_t len;
};

static size_t write_mem(char *ptr, size_t size, size_t nmemb, void *userdata) {
  struct mem_buf *m = (struct mem_buf *)userdata;
  size_t n = size * nmemb;
  char *p = (char *)realloc(m->data, m->len + n + 1);
  if (!p) return 0;
  m->data = p;
  memcpy(m->data + m->len, ptr, n);
  m->len += n;
  m->data[m->len] = '\0';
  return n;
}

static size_t write_file(char *ptr, size_t size, size_t nmemb, void *userdata) {
  return fwrite(ptr, size, nmemb, (FILE *)userdata);
}
#endif

int ota_net_download_buffer(const char *url, long timeout_ms, char **out, size_t *out_len,
                            char *err, size_t err_len) {
  if (out) *out = NULL;
  if (out_len) *out_len = 0;
  if (!url || !out) {
    if (err && err_len) snprintf(err, err_len, "bad args");
    return -1;
  }
#if defined(__SWITCH__)
  CURL *curl = curl_easy_init();
  if (!curl) {
    if (err && err_len) snprintf(err, err_len, "curl_easy_init failed");
    return -1;
  }
  struct mem_buf mem = {0};
  curl_easy_setopt(curl, CURLOPT_URL, url);
  curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
  curl_easy_setopt(curl, CURLOPT_USERAGENT, "gen1recomp-switch-ota");
  curl_easy_setopt(curl, CURLOPT_TIMEOUT_MS, timeout_ms);
  curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT_MS, timeout_ms);
  curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_mem);
  curl_easy_setopt(curl, CURLOPT_WRITEDATA, &mem);
  /* Atmosphere / homebrew CA store is limited; match common homebrew practice. */
  curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 0L);
  curl_easy_setopt(curl, CURLOPT_SSL_VERIFYHOST, 0L);
  CURLcode rc = curl_easy_perform(curl);
  curl_easy_cleanup(curl);
  if (rc != CURLE_OK) {
    free(mem.data);
    if (err && err_len) snprintf(err, err_len, "%s", curl_easy_strerror(rc));
    return -1;
  }
  *out = mem.data;
  if (out_len) *out_len = mem.len;
  return 0;
#else
  (void)timeout_ms;
  if (err && err_len)
    snprintf(err, err_len, "ota_net_download_buffer only available on __SWITCH__");
  return -1;
#endif
}

int ota_net_download_file(const char *url, const char *path, long timeout_ms, char *err,
                          size_t err_len) {
  if (!url || !path) {
    if (err && err_len) snprintf(err, err_len, "bad args");
    return -1;
  }
#if defined(__SWITCH__)
  FILE *fp = fopen(path, "wb");
  if (!fp) {
    if (err && err_len) snprintf(err, err_len, "fopen failed: %s", path);
    return -1;
  }
  CURL *curl = curl_easy_init();
  if (!curl) {
    fclose(fp);
    if (err && err_len) snprintf(err, err_len, "curl_easy_init failed");
    return -1;
  }
  curl_easy_setopt(curl, CURLOPT_URL, url);
  curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
  curl_easy_setopt(curl, CURLOPT_USERAGENT, "gen1recomp-switch-ota");
  curl_easy_setopt(curl, CURLOPT_TIMEOUT_MS, timeout_ms);
  curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT_MS, timeout_ms);
  curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_file);
  curl_easy_setopt(curl, CURLOPT_WRITEDATA, fp);
  curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 0L);
  curl_easy_setopt(curl, CURLOPT_SSL_VERIFYHOST, 0L);
  CURLcode rc = curl_easy_perform(curl);
  curl_easy_cleanup(curl);
  fclose(fp);
  if (rc != CURLE_OK) {
    if (err && err_len) snprintf(err, err_len, "%s", curl_easy_strerror(rc));
    return -1;
  }
  return 0;
#else
  (void)timeout_ms;
  if (err && err_len)
    snprintf(err, err_len, "ota_net_download_file only available on __SWITCH__");
  return -1;
#endif
}
