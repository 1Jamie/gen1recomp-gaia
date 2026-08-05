/*
 * gen1recomp Switch OTA launcher
 *
 * Quiet by default: checks GitHub Releases with no console flash. Only shows
 * a short prompt when an update is available. Downloads the same SD zip
 * published for install (gen1recomp-*-switch.zip), verifies SHA-256, extracts
 * switch/gen1recomp/gen1recomp-game.nro, then envSetNextLoad to the game.
 * Never touches pokemon-love2d/. LÖVE self-updater stays off on NX.
 */

#include "ota_fs.h"
#include "ota_net.h"
#include "ota_protocol.h"
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

#if defined(__SWITCH__)
static int g_ui = 0;

static void ui_begin(void) {
  if (g_ui) return;
  consoleInit(NULL);
  consoleClear();
  g_ui = 1;
}

static void ui_end(void) {
  if (!g_ui) return;
  consoleExit(NULL);
  g_ui = 0;
}

static void ui_line(const char *msg) {
  ui_begin();
  printf("%s\n", msg);
  consoleUpdate(NULL);
}

static void ui_blank(void) {
  if (!g_ui) return;
  consoleClear();
  consoleUpdate(NULL);
}
#else
static void ui_begin(void) {}
static void ui_end(void) {}
static void ui_line(const char *msg) { fprintf(stderr, "%s\n", msg); }
static void ui_blank(void) {}
#endif

/* Returns 1 = update, 0 = skip. Only called when UI is already needed. */
static int wait_confirm_or_skip(void) {
#if defined(__SWITCH__)
  PadState pad;
  padInitializeDefault(&pad);
  ui_line("");
  ui_line("  A — Update");
  ui_line("  B — Play without updating");
  while (appletMainLoop()) {
    padUpdate(&pad);
    u64 k = padGetButtonsDown(&pad);
    if (k & HidNpadButton_A) return 1;
    if (k & HidNpadButton_B) return 0;
    consoleUpdate(NULL);
  }
  return 0;
#else
  return 0;
#endif
}

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

  /* Update available — only now show UI */
  {
    char msg[160];
    ui_blank();
    ui_line("");
    ui_line("  gen1recomp");
    ui_line("");
    snprintf(msg, sizeof(msg), "  Update available: %s → %s", installed, dec.version);
    ui_line(msg);
  }

  if (!wait_confirm_or_skip()) {
    ui_end();
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

  ui_blank();
  ui_line("");
  ui_line("  Downloading…");
  if (ota_net_download_file(dec.download_url, zip_path, 180000L, err, sizeof(err)) != 0) {
    ui_line("");
    ui_line("  Download failed.");
    ui_line("  Playing the installed version.");
#if defined(__SWITCH__)
    {
      PadState pad;
      padInitializeDefault(&pad);
      ui_line("");
      ui_line("  Press B to continue");
      while (appletMainLoop()) {
        padUpdate(&pad);
        if (padGetButtonsDown(&pad) & HidNpadButton_B) break;
        consoleUpdate(NULL);
      }
    }
#endif
    ui_end();
    return 0;
  }

  char sums_url[512];
  snprintf(sums_url, sizeof(sums_url),
           "https://github.com/bryanthaboi/gen1recomp/releases/download/%s/sha256sums.txt",
           rel.tag);
  if (ota_net_download_file(sums_url, sums_path, CHECK_TIMEOUT_MS, err, sizeof(err)) != 0) {
    ui_line("");
    ui_line("  Could not verify the update.");
    ui_line("  Playing the installed version.");
    remove(zip_path);
    ui_end();
#if defined(__SWITCH__)
    svcSleepThread(1200000000ULL);
#endif
    return 0;
  }

  FILE *sf = fopen(sums_path, "rb");
  if (!sf) {
    remove(zip_path);
    ui_end();
    return 0;
  }
  fseek(sf, 0, SEEK_END);
  long slen = ftell(sf);
  fseek(sf, 0, SEEK_SET);
  char *sums = (char *)malloc((size_t)slen + 1);
  if (!sums) {
    fclose(sf);
    ui_end();
    return 0;
  }
  fread(sums, 1, (size_t)slen, sf);
  sums[slen] = '\0';
  fclose(sf);

  char hex[96];
  if (ota_fs_sha256_file(zip_path, hex, sizeof(hex)) != 0) {
    free(sums);
    remove(zip_path);
    ui_end();
    return 0;
  }
  ota_verify_t ver;
  ota_verify_sha256(dec.asset_name, hex, sums, &ver);
  free(sums);
  if (!ver.ok) {
    ui_line("");
    ui_line("  Update file failed checks.");
    ui_line("  Playing the installed version.");
    remove(zip_path);
    ui_end();
#if defined(__SWITCH__)
    svcSleepThread(1200000000ULL);
#endif
    return 0;
  }

  char extracted[256];
  char extracted_launcher[256];
  snprintf(extracted, sizeof(extracted), "%s/updates/gen1recomp-game.nro.verified", install_dir);
  snprintf(extracted_launcher, sizeof(extracted_launcher),
           "%s/updates/gen1recomp.nro.verified", install_dir);

#if defined(__SWITCH__)
  ui_line("");
  ui_line("  Installing…");
  /* Prefer path inside SD zip; fall back to bare name. */
  if (ota_unzip_extract_file(zip_path, GAME_MEMBER_IN_ZIP, extracted, err, sizeof(err)) != 0) {
    if (ota_unzip_extract_file(zip_path, OTA_GAME_NRO_NAME, extracted, err, sizeof(err)) != 0) {
      ui_line("");
      ui_line("  Install failed.");
      ui_line("  Playing the installed version.");
      remove(zip_path);
      ui_end();
      svcSleepThread(1200000000ULL);
      return 0;
    }
  }

  if (ota_fs_atomic_replace_game(install_dir, extracted, err, sizeof(err)) != 0) {
    ui_line("");
    ui_line("  Install failed.");
    ui_line("  Playing the installed version.");
    remove(extracted);
    remove(zip_path);
    ui_end();
    svcSleepThread(1200000000ULL);
    return 0;
  }
  remove(extracted);

  /* Also replace launcher so hbmenu/Sphaira see the matching NACP version.
   * Best-effort: game update already succeeded if this fails. */
  if (ota_unzip_extract_file(zip_path, LAUNCHER_MEMBER_IN_ZIP, extracted_launcher, err,
                             sizeof(err)) == 0 ||
      ota_unzip_extract_file(zip_path, OTA_LAUNCHER_NRO_NAME, extracted_launcher, err,
                             sizeof(err)) == 0) {
    if (ota_fs_atomic_replace_nro(install_dir, OTA_LAUNCHER_NRO_NAME, extracted_launcher, err,
                                  sizeof(err)) == 0) {
      remove(extracted_launcher);
    } else {
      remove(extracted_launcher);
    }
  }

  char vpath[192];
  snprintf(vpath, sizeof(vpath), "%s/version.txt", install_dir);
  FILE *vf = fopen(vpath, "wb");
  if (vf) {
    fprintf(vf, "%s\n", dec.version);
    fclose(vf);
  }
#else
  (void)extracted;
  (void)extracted_launcher;
#endif
  remove(zip_path);
  ui_end();
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
    ui_line("");
    ui_line("  gen1recomp");
    ui_line("");
    ui_line("  Game files are missing.");
    ui_line("  Copy the Switch zip onto your microSD,");
    ui_line("  then open gen1recomp again.");
#if defined(__SWITCH__)
    ui_line("");
    ui_line("  Press + to exit");
    PadState pad;
    padInitializeDefault(&pad);
    while (appletMainLoop()) {
      padUpdate(&pad);
      if (padGetButtonsDown(&pad) & HidNpadButton_Plus) break;
      consoleUpdate(NULL);
    }
#endif
    ui_end();
  }

#if defined(__SWITCH__)
  socketExit();
#endif
  return 0;
}
