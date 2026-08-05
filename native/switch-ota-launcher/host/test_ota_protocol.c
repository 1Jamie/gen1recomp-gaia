/* Host-only unit tests for ota_protocol.c — no libnx. */
#include "ota_protocol.h"

#include <stdio.h>
#include <string.h>

static int g_fail = 0;

static void expect(int cond, const char *msg) {
  if (!cond) {
    fprintf(stderr, "FAIL: %s\n", msg);
    g_fail++;
  } else {
    printf("PASS: %s\n", msg);
  }
}

int main(void) {
  expect(ota_compare_semver("1.2.0", "1.1.0") == 1, "semver newer");
  expect(ota_compare_semver("1.1.0", "1.1.0") == 0, "semver equal");
  expect(ota_compare_semver("1.0.0", "1.1.0") == -1, "semver older");
  expect(ota_is_ota_asset_name("gen1recomp-1.5.0-switch.zip"), "ota asset name");
  expect(!ota_is_ota_asset_name("gen1recomp-1.5.0-switch-ota.zip"), "reject legacy ota zip name");
  expect(!ota_is_ota_asset_name("gen1recomp-1.5.0.love"), "reject love payload");

  const char *json =
      "{"
      "\"tag_name\":\"v1.5.0\","
      "\"assets\":["
      "{\"name\":\"gen1recomp-1.5.0-switch.zip\","
      "\"browser_download_url\":\"https://example/switch.zip\"},"
      "{\"name\":\"sha256sums.txt\",\"browser_download_url\":\"https://example/sums\"}"
      "]"
      "}";
  ota_release_t rel;
  expect(ota_parse_release(json, &rel) == 1, "parse release");
  expect(strcmp(rel.version, "1.5.0") == 0, "release version");
  expect(strcmp(rel.asset_name, "gen1recomp-1.5.0-switch.zip") == 0, "release asset");

  ota_decision_t d;
  ota_decide_update("1.4.0", &rel, &d);
  expect(strcmp(d.status, "available") == 0, "decide available");
  ota_decide_update("1.5.0", &rel, &d);
  expect(strcmp(d.status, "uptodate") == 0, "decide uptodate");

  ota_release_t bad;
  expect(ota_parse_release("{\"tag_name\":\"v1.5.0\",\"assets\":[]}", &bad) == 0,
         "missing ota asset");
  expect(strcmp(bad.reason, "missing_ota_asset") == 0, "missing_ota_asset reason");

  const char *sums = "abc123  gen1recomp-1.5.0-switch.zip\n";
  ota_verify_t v;
  ota_verify_sha256("gen1recomp-1.5.0-switch.zip", "abc123", sums, &v);
  expect(v.ok == 1, "sha ok");
  ota_verify_sha256("gen1recomp-1.5.0-switch.zip", "deadbeef", sums, &v);
  expect(v.ok == 0 && strcmp(v.reason, "hash_mismatch") == 0, "sha mismatch");
  ota_verify_sha256("gen1recomp-1.5.0-switch.zip", "abc123", "", &v);
  expect(v.ok == 0 && strcmp(v.reason, "sum_not_found") == 0, "sha missing sum rejected");

  ota_apply_plan_t plan;
  ota_plan_atomic_apply("switch/gen1recomp", "/tmp/x", &plan);
  expect(strstr(plan.steps[0], "copy_to_part:") != NULL, "plan copy");
  expect(strstr(plan.steps[1], "rename:") != NULL, "plan rename");
  expect(strstr(plan.steps[2], "copy_to_part:launcher") != NULL, "plan launcher copy");
  expect(strstr(plan.steps[3], "rename:") != NULL, "plan launcher rename");
  expect(strstr(plan.steps[4], "env_set_next_load:") != NULL, "plan handoff");
  expect(strstr(plan.preserve, "pokemon-love2d") != NULL, "preserve saves");
  expect(strstr(plan.forbidden_delete, "delete:") != NULL, "forbid delete saves");
  expect(strstr(plan.forbidden_direct, "write_direct:") != NULL, "forbid direct write");

  ota_offline_t off;
  ota_offline_events_t ev = {0};
  ev.user_skip = 1;
  ota_offline_policy(1.0, &ev, &off);
  expect(strcmp(off.action, "play_installed") == 0, "skip plays installed");
  ev.user_skip = 0;
  ev.network_ok = 0;
  ota_offline_policy(1.0, &ev, &off);
  expect(strcmp(off.action, "play_installed") == 0, "offline plays installed");
  ev.network_ok = 1;
  ota_offline_policy(6.0, &ev, &off);
  expect(strcmp(off.reason, "timeout") == 0, "timeout 6s");
  ota_offline_policy(2.0, &ev, &off);
  expect(strcmp(off.action, "keep_checking") == 0, "still checking");

  expect(OTA_CHECK_TIMEOUT_SEC == 6, "timeout constant 6");

  if (g_fail) {
    fprintf(stderr, "%d failure(s)\n", g_fail);
    return 1;
  }
  printf("all ota_protocol host tests passed\n");
  return 0;
}
