/*
 * Switch OTA UI — matches in-game launcher language (Theme.lua):
 * black field, RGB version rail, flat yellow/white buttons, white ink.
 * Quiet until called. Uses framebuffer + 8x8 font + optional romfs logo.
 */
#include "ota_ui.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(__SWITCH__)
#include <switch.h>

#define STB_IMAGE_IMPLEMENTATION
#define STBI_ONLY_PNG
#define STBI_NO_THREAD_LOCALS
#include "../third_party/stb_image.h"
#include "../third_party/font8x8_basic.h"

#define FB_W 1280
#define FB_H 720

/* Theme.PAL (0–255) → RGBA8 */
#define COL_BG RGBA8_MAXALPHA(0, 0, 0)
#define COL_INK RGBA8_MAXALPHA(255, 255, 255)
#define COL_DETAIL RGBA8_MAXALPHA(200, 200, 200)
#define COL_MUTED RGBA8_MAXALPHA(150, 150, 150)
#define COL_INVERSE RGBA8_MAXALPHA(0, 0, 0)
#define COL_YELLOW RGBA8_MAXALPHA(255, 214, 0)
#define COL_GREEN RGBA8_MAXALPHA(0, 255, 140)
#define COL_RAIL_R RGBA8_MAXALPHA(255, 60, 72)
#define COL_RAIL_B RGBA8_MAXALPHA(70, 150, 255)
#define COL_RAIL_G RGBA8_MAXALPHA(255, 203, 5)
#define COL_LINE RGBA8_MAXALPHA(90, 90, 90)
#define COL_RAISED RGBA8_MAXALPHA(20, 20, 20)

static int g_ready = 0;
static Framebuffer g_fb;
static PadState g_pad;
static u32 *g_logo = NULL;
static int g_logo_w = 0, g_logo_h = 0;

static void fill_rect(u32 *fb, u32 stride_px, int x, int y, int w, int h, u32 color) {
  if (w <= 0 || h <= 0) return;
  if (x < 0) {
    w += x;
    x = 0;
  }
  if (y < 0) {
    h += y;
    y = 0;
  }
  if (x + w > FB_W) w = FB_W - x;
  if (y + h > FB_H) h = FB_H - y;
  if (w <= 0 || h <= 0) return;
  for (int row = 0; row < h; row++) {
    u32 *line = fb + (y + row) * stride_px + x;
    for (int col = 0; col < w; col++) line[col] = color;
  }
}

static void draw_glyph(u32 *fb, u32 stride_px, int x, int y, char ch, u32 color, int scale) {
  unsigned char c = (unsigned char)ch;
  if (c > 127) c = '?';
  const char *bits = font8x8_basic[c];
  for (int row = 0; row < 8; row++) {
    unsigned char line = (unsigned char)bits[row];
    for (int col = 0; col < 8; col++) {
      if (line & (1 << col)) {
        fill_rect(fb, stride_px, x + col * scale, y + row * scale, scale, scale, color);
      }
    }
  }
}

static int text_width(const char *s, int scale) {
  if (!s) return 0;
  return (int)strlen(s) * 8 * scale;
}

static void draw_text(u32 *fb, u32 stride_px, int x, int y, const char *s, u32 color, int scale) {
  if (!s) return;
  int cx = x;
  for (; *s; s++) {
    if (*s == '\n') {
      cx = x;
      y += 8 * scale + 4;
      continue;
    }
    draw_glyph(fb, stride_px, cx, y, *s, color, scale);
    cx += 8 * scale;
  }
}

static void draw_text_centered(u32 *fb, u32 stride_px, int y, const char *s, u32 color, int scale) {
  int w = text_width(s, scale);
  draw_text(fb, stride_px, (FB_W - w) / 2, y, s, color, scale);
}

static void draw_rail(u32 *fb, u32 stride_px) {
  int h = 6;
  int third = FB_W / 3;
  fill_rect(fb, stride_px, 0, 0, third, h, COL_RAIL_R);
  fill_rect(fb, stride_px, third, 0, third, h, COL_RAIL_B);
  fill_rect(fb, stride_px, third * 2, 0, FB_W - third * 2, h, COL_RAIL_G);
}

static void blit_logo(u32 *fb, u32 stride_px, int dst_x, int dst_y, int max_w) {
  if (!g_logo || g_logo_w <= 0 || g_logo_h <= 0) return;
  int dw = g_logo_w;
  int dh = g_logo_h;
  if (dw > max_w) {
    dh = dh * max_w / dw;
    dw = max_w;
  }
  for (int y = 0; y < dh; y++) {
    int sy = y * g_logo_h / dh;
    for (int x = 0; x < dw; x++) {
      int sx = x * g_logo_w / dw;
      u32 px = g_logo[sy * g_logo_w + sx];
      u8 a = (px >> 24) & 0xff;
      if (a < 16) continue;
      int dx = dst_x + x;
      int dy = dst_y + y;
      if (dx < 0 || dy < 0 || dx >= FB_W || dy >= FB_H) continue;
      fb[dy * stride_px + dx] = px | 0xff000000u;
    }
  }
}

static void load_logo(void) {
  if (g_logo) return;
  romfsInit();
  int w = 0, h = 0, n = 0;
  unsigned char *data = stbi_load("romfs:/logo.png", &w, &h, &n, 4);
  if (!data || w <= 0 || h <= 0) {
    if (data) stbi_image_free(data);
    return;
  }
  g_logo = (u32 *)malloc((size_t)w * (size_t)h * sizeof(u32));
  if (!g_logo) {
    stbi_image_free(data);
    return;
  }
  for (int i = 0; i < w * h; i++) {
    unsigned char *p = data + i * 4;
    /* Premultiply-ish: keep RGB, store A in high byte for skip */
    g_logo[i] = RGBA8(p[0], p[1], p[2], p[3]);
  }
  g_logo_w = w;
  g_logo_h = h;
  stbi_image_free(data);
}

static int ui_ensure(void) {
  if (g_ready) return 1;
  NWindow *win = nwindowGetDefault();
  if (R_FAILED(framebufferCreate(&g_fb, win, FB_W, FB_H, PIXEL_FORMAT_RGBA_8888, 2))) return 0;
  framebufferMakeLinear(&g_fb);
  padInitializeDefault(&g_pad);
  load_logo();
  g_ready = 1;
  return 1;
}

void ota_ui_shutdown(void) {
  if (!g_ready) return;
  framebufferClose(&g_fb);
  free(g_logo);
  g_logo = NULL;
  g_logo_w = g_logo_h = 0;
  romfsExit();
  g_ready = 0;
}

static void draw_button(u32 *fb, u32 stride_px, int x, int y, int w, int h, u32 fill, u32 ink,
                        const char *label, int focused) {
  fill_rect(fb, stride_px, x, y, w, h, fill);
  if (focused) {
    /* 2px white focus ring (launcher focus outline) */
    fill_rect(fb, stride_px, x - 3, y - 3, w + 6, 2, COL_INK);
    fill_rect(fb, stride_px, x - 3, y + h + 1, w + 6, 2, COL_INK);
    fill_rect(fb, stride_px, x - 3, y - 3, 2, h + 6, COL_INK);
    fill_rect(fb, stride_px, x + w + 1, y - 3, 2, h + 6, COL_INK);
  } else {
    fill_rect(fb, stride_px, x, y, w, 1, COL_LINE);
    fill_rect(fb, stride_px, x, y + h - 1, w, 1, COL_LINE);
    fill_rect(fb, stride_px, x, y, 1, h, COL_LINE);
    fill_rect(fb, stride_px, x + w - 1, y, 1, h, COL_LINE);
  }
  int scale = 3;
  int tw = text_width(label, scale);
  int tx = x + (w - tw) / 2;
  int ty = y + (h - 8 * scale) / 2;
  draw_text(fb, stride_px, tx, ty, label, ink, scale);
}

static void draw_chrome(u32 *fb, u32 stride_px) {
  fill_rect(fb, stride_px, 0, 0, FB_W, FB_H, COL_BG);
  draw_rail(fb, stride_px);
  int logo_max = 320;
  int logo_h = g_logo ? (g_logo_h * logo_max / g_logo_w) : 40;
  if (logo_h > 90) logo_h = 90;
  int logo_y = 48;
  if (g_logo) {
    int logo_w = logo_max;
    if (g_logo_w * logo_h / g_logo_h < logo_max) logo_w = g_logo_w * logo_h / g_logo_h;
    blit_logo(fb, stride_px, (FB_W - logo_w) / 2, logo_y, logo_max);
  } else {
    draw_text_centered(fb, stride_px, logo_y + 16, "gen1recomp", COL_INK, 4);
  }
}

static void present(void (*paint)(u32 *fb, u32 stride_px, void *ctx), void *ctx) {
  if (!ui_ensure()) return;
  u32 stride = 0;
  u32 *fb = (u32 *)framebufferBegin(&g_fb, &stride);
  u32 stride_px = stride / sizeof(u32);
  paint(fb, stride_px, ctx);
  framebufferEnd(&g_fb);
}

typedef struct {
  const char *installed;
  const char *latest;
  int focus; /* 0 = Update, 1 = Play */
} prompt_ctx_t;

static void paint_prompt(u32 *fb, u32 stride_px, void *ctx) {
  prompt_ctx_t *p = (prompt_ctx_t *)ctx;
  draw_chrome(fb, stride_px);

  int y = 180;
  draw_text_centered(fb, stride_px, y, "Update available", COL_INK, 3);
  y += 48;

  char line[96];
  snprintf(line, sizeof(line), "v%s  ->  v%s", p->installed ? p->installed : "?",
           p->latest ? p->latest : "?");
  draw_text_centered(fb, stride_px, y, line, COL_YELLOW, 3);
  y += 56;

  draw_text_centered(fb, stride_px, y, "Your saves stay on this console.", COL_MUTED, 2);
  y += 64;

  int bw = 420;
  int bh = 64;
  int bx = (FB_W - bw) / 2;
  draw_button(fb, stride_px, bx, y, bw, bh, COL_YELLOW, COL_INVERSE, "A  Update", p->focus == 0);
  y += bh + 24;
  draw_button(fb, stride_px, bx, y, bw, bh, COL_INK, COL_INVERSE, "B  Play without updating",
              p->focus == 1);
}

int ota_ui_prompt_update(const char *installed, const char *latest) {
  if (!ui_ensure()) return 0;
  prompt_ctx_t ctx = {installed, latest, 0};
  while (appletMainLoop()) {
    present(paint_prompt, &ctx);
    padUpdate(&g_pad);
    u64 k = padGetButtonsDown(&g_pad);
    if (k & HidNpadButton_A) {
      int do_update = (ctx.focus == 0);
      if (!do_update) ota_ui_shutdown();
      return do_update;
    }
    if (k & HidNpadButton_B) {
      ota_ui_shutdown();
      return 0;
    }
    if (k & (HidNpadButton_Up | HidNpadButton_Down | HidNpadButton_Left | HidNpadButton_Right)) {
      ctx.focus = 1 - ctx.focus;
    }
    svcSleepThread(16000000ULL);
  }
  ota_ui_shutdown();
  return 0;
}

typedef struct {
  const char *title;
  const char *detail;
  float progress;
  int show_bar;
} status_ctx_t;

static void paint_status(u32 *fb, u32 stride_px, void *ctx) {
  status_ctx_t *s = (status_ctx_t *)ctx;
  draw_chrome(fb, stride_px);
  int y = 200;
  draw_text_centered(fb, stride_px, y, s->title ? s->title : "", COL_INK, 3);
  y += 48;
  if (s->detail && s->detail[0]) {
    draw_text_centered(fb, stride_px, y, s->detail, COL_DETAIL, 2);
    y += 40;
  }
  if (s->show_bar) {
    int bw = 520;
    int bh = 18;
    int bx = (FB_W - bw) / 2;
    float t = s->progress;
    if (t < 0.f) t = 0.f;
    if (t > 1.f) t = 1.f;
    fill_rect(fb, stride_px, bx, y, bw, bh, COL_RAISED);
    fill_rect(fb, stride_px, bx, y, bw, 1, COL_LINE);
    fill_rect(fb, stride_px, bx, y + bh - 1, bw, 1, COL_LINE);
    fill_rect(fb, stride_px, bx, y, 1, bh, COL_LINE);
    fill_rect(fb, stride_px, bx + bw - 1, y, 1, bh, COL_LINE);
    int fw = (int)(bw * t);
    if (fw > 0) fill_rect(fb, stride_px, bx, y, fw, bh, COL_GREEN);
  }
}

void ota_ui_show_status(const char *title, const char *detail) {
  status_ctx_t s = {title, detail, 0.f, 0};
  present(paint_status, &s);
}

void ota_ui_show_progress(const char *title, const char *detail, float progress01) {
  status_ctx_t s = {title, detail, progress01, 1};
  present(paint_status, &s);
}

typedef struct {
  const char *title;
  const char *line1;
  const char *line2;
} alert_ctx_t;

static void paint_alert(u32 *fb, u32 stride_px, void *ctx) {
  alert_ctx_t *a = (alert_ctx_t *)ctx;
  draw_chrome(fb, stride_px);
  int y = 200;
  draw_text_centered(fb, stride_px, y, a->title ? a->title : "", COL_YELLOW, 3);
  y += 52;
  if (a->line1) draw_text_centered(fb, stride_px, y, a->line1, COL_DETAIL, 2);
  y += 36;
  if (a->line2) draw_text_centered(fb, stride_px, y, a->line2, COL_MUTED, 2);
  y += 64;
  int bw = 360;
  int bh = 56;
  draw_button(fb, stride_px, (FB_W - bw) / 2, y, bw, bh, COL_INK, COL_INVERSE, "B  Continue", 1);
}

void ota_ui_alert(const char *title, const char *line1, const char *line2) {
  if (!ui_ensure()) return;
  alert_ctx_t a = {title, line1, line2};
  while (appletMainLoop()) {
    present(paint_alert, &a);
    padUpdate(&g_pad);
    if (padGetButtonsDown(&g_pad) & HidNpadButton_B) break;
    svcSleepThread(16000000ULL);
  }
  ota_ui_shutdown();
}

static void paint_missing(u32 *fb, u32 stride_px, void *ctx) {
  (void)ctx;
  draw_chrome(fb, stride_px);
  int y = 190;
  draw_text_centered(fb, stride_px, y, "Game files missing", COL_YELLOW, 3);
  y += 52;
  draw_text_centered(fb, stride_px, y, "Copy the Switch zip onto your microSD,", COL_DETAIL, 2);
  y += 32;
  draw_text_centered(fb, stride_px, y, "then open gen1recomp again.", COL_DETAIL, 2);
  y += 64;
  int bw = 320;
  int bh = 56;
  draw_button(fb, stride_px, (FB_W - bw) / 2, y, bw, bh, COL_INK, COL_INVERSE, "+  Exit", 1);
}

void ota_ui_missing_game(void) {
  if (!ui_ensure()) return;
  while (appletMainLoop()) {
    present(paint_missing, NULL);
    padUpdate(&g_pad);
    if (padGetButtonsDown(&g_pad) & HidNpadButton_Plus) break;
    svcSleepThread(16000000ULL);
  }
  ota_ui_shutdown();
}

#else /* host stub */

int ota_ui_prompt_update(const char *installed, const char *latest) {
  fprintf(stderr, "[ota_ui] update %s -> %s (host stub: skip)\n", installed ? installed : "?",
          latest ? latest : "?");
  return 0;
}
void ota_ui_show_status(const char *title, const char *detail) {
  fprintf(stderr, "[ota_ui] %s %s\n", title ? title : "", detail ? detail : "");
}
void ota_ui_show_progress(const char *title, const char *detail, float progress01) {
  fprintf(stderr, "[ota_ui] %s %s (%.0f%%)\n", title ? title : "", detail ? detail : "",
          progress01 * 100.f);
}
void ota_ui_alert(const char *title, const char *line1, const char *line2) {
  fprintf(stderr, "[ota_ui] alert: %s / %s / %s\n", title ? title : "", line1 ? line1 : "",
          line2 ? line2 : "");
}
void ota_ui_missing_game(void) { fprintf(stderr, "[ota_ui] missing game\n"); }
void ota_ui_shutdown(void) {}

#endif
