/*
 * gen1recomp Switch OTA launcher
 *
 * Quiet by default: checks GitHub Releases with no UI. Only shows the
 * branded launcher-style screen when an update is available. Downloads the
 * same SD zip (gen1recomp-*-switch.zip), verifies SHA-256, replaces game +
 * launcher NROs, then envSetNextLoad. Never touches pokemon-love2d/.
 * LÖVE self-updater stays off on NX.
 */

#include "ota_fs.h"
#include "ota_net.h"
#include "ota_protocol.h"
#include "ota_ui.h"
#include "ota_unzip.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(__SWITCH__)
#include <sys/stat.h>
#include <switch.h>
#include <unistd.h>
#else
#include <sys/stat.h>
#include <unistd.h>
#endif

#define SD_INSTALL_DIR "sdmc:/switch/gen1recomp"
#define CHECK_TIMEOUT_MS (OTA_CHECK_TIMEOUT_SEC * 1000L)
#define GAME_MEMBER_IN_ZIP "switch/gen1recomp/" OTA_GAME_NRO_NAME
#define LAUNCHER_MEMBER_IN_ZIP "switch/gen1recomp/" OTA_LAUNCHER_NRO_NAME

static int run_update_flow(const char *install_dir) {
  char installed[64] = "0.0.0";
  (void)ota_fs_read_installed_version(install_dir, installed, sizeof(installed));

  char *json = NULL;
  size_t json_len = 0;
  char err[256];
  err[0] = '\0';

  if (ota_net_download_buffer(OTA_RELEASES_API, CHECK_TIMEOUT_MS, &json, &json_len, err,
                              sizeof(err)) != 0) {
    free(json);
    return 0; /* offline / timeout — play installed, no UI */
  }

  ota_release_t rel;
  if (!ota_parse_release(json, &rel)) {
    free(json);
    return 0;
  }
  free(json);

  ota_decision_t dec;
  ota_decide_update(installed, &rel, &dec);
  if (strcmp(dec.status, "uptodate") == 0 || strcmp(dec.status, "error") == 0) {
    return 0;
  }

  if (!ota_ui_prompt_update(installed, dec.version)) {
    return 0;
  }

  char updates_dir[192];
  char zip_path[256];
  char sums_path[256];
  snprintf(updates_dir, sizeof(updates_dir), "%s/updates", install_dir);
  snprintf(zip_path, sizeof(zip_path), "%s/updates/%s", install_dir, dec.asset_name);
  snprintf(sums_path, sizeof(sums_path), "%s/updates/sha256sums.txt", install_dir);

#if defined(__SWITCH__)
  mkdir(updates_dir, 0755);
#endif

  ota_ui_show_progress("Downloading…", "This may take a minute.", 0.15f);
  if (ota_net_download_file(dec.download_url, zip_path, 180000L, err, sizeof(err)) != 0) {
    ota_ui_alert("Download failed", "Playing the installed version.", NULL);
    return 0;
  }

  ota_ui_show_progress("Checking update…", "Verifying file integrity.", 0.55f);
  char sums_url[512];
  snprintf(sums_url, sizeof(sums_url),
           "https://github.com/bryanthaboi/gen1recomp/releases/download/%s/sha256sums.txt",
           rel.tag);
  if (ota_net_download_file(sums_url, sums_path, CHECK_TIMEOUT_MS, err, sizeof(err)) != 0) {
    remove(zip_path);
    ota_ui_alert("Could not verify", "Playing the installed version.", NULL);
    return 0;
  }

  FILE *sf = fopen(sums_path, "rb");
  if (!sf) {
    remove(zip_path);
    ota_ui_shutdown();
    return 0;
  }
  fseek(sf, 0, SEEK_END);
  long slen = ftell(sf);
  fseek(sf, 0, SEEK_SET);
  char *sums = (char *)malloc((size_t)slen + 1);
  if (!sums) {
    fclose(sf);
    ota_ui_shutdown();
    return 0;
  }
  fread(sums, 1, (size_t)slen, sf);
  sums[slen] = '\0';
  fclose(sf);

  char hex[96];
  if (ota_fs_sha256_file(zip_path, hex, sizeof(hex)) != 0) {
    free(sums);
    remove(zip_path);
    ota_ui_shutdown();
    return 0;
  }
  ota_verify_t ver;
  ota_verify_sha256(dec.asset_name, hex, sums, &ver);
  free(sums);
  if (!ver.ok) {
    remove(zip_path);
    ota_ui_alert("Update check failed", "Playing the installed version.", NULL);
    return 0;
  }

  char extracted[256];
  char extracted_launcher[256];
  snprintf(extracted, sizeof(extracted), "%s/updates/gen1recomp-game.nro.verified", install_dir);
  snprintf(extracted_launcher, sizeof(extracted_launcher), "%s/updates/gen1recomp.nro.verified",
           install_dir);

#if defined(__SWITCH__)
  ota_ui_show_progress("Installing…", "Keeping your saves safe.", 0.8f);
  if (ota_unzip_extract_file(zip_path, GAME_MEMBER_IN_ZIP, extracted, err, sizeof(err)) != 0) {
    if (ota_unzip_extract_file(zip_path, OTA_GAME_NRO_NAME, extracted, err, sizeof(err)) != 0) {
      remove(zip_path);
      ota_ui_alert("Install failed", "Playing the installed version.", NULL);
      return 0;
    }
  }

  if (ota_fs_atomic_replace_game(install_dir, extracted, err, sizeof(err)) != 0) {
    remove(extracted);
    remove(zip_path);
    ota_ui_alert("Install failed", "Playing the installed version.", NULL);
    return 0;
  }
  remove(extracted);

  if (ota_unzip_extract_file(zip_path, LAUNCHER_MEMBER_IN_ZIP, extracted_launcher, err,
                             sizeof(err)) == 0 ||
      ota_unzip_extract_file(zip_path, OTA_LAUNCHER_NRO_NAME, extracted_launcher, err,
                             sizeof(err)) == 0) {
    (void)ota_fs_atomic_replace_nro(install_dir, OTA_LAUNCHER_NRO_NAME, extracted_launcher, err,
                                    sizeof(err));
    remove(extracted_launcher);
  }

  char vpath[192];
  snprintf(vpath, sizeof(vpath), "%s/version.txt", install_dir);
  FILE *vf = fopen(vpath, "wb");
  if (vf) {
    fprintf(vf, "%s\n", dec.version);
    fclose(vf);
  }

  ota_ui_show_progress("Ready", "Starting the game…", 1.0f);
  svcSleepThread(600000000ULL);
#else
  (void)extracted;
  (void)extracted_launcher;
#endif
  remove(zip_path);
  ota_ui_shutdown();
  return 0;
}

int main(int argc, char **argv) {
  (void)argc;
  (void)argv;

#if defined(__SWITCH__)
  socketInitializeDefault();
  padConfigureInput(1, HidNpadStyleSet_NpadStandard);
#endif

  const char *install = SD_INSTALL_DIR;
  run_update_flow(install);

  char game[192];
  snprintf(game, sizeof(game), "%s/%s", install, OTA_GAME_NRO_NAME);
  char err[128];
  err[0] = '\0';
  if (ota_fs_handoff_to_game(game, err, sizeof(err)) != 0) {
    ota_ui_missing_game();
  }

  ota_ui_shutdown();

#if defined(__SWITCH__)
  socketExit();
#endif
  return 0;
}
