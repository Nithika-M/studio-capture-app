#include "floating_bar.h"

#include <cstdio>
#include <cwchar>

namespace {
const wchar_t kClassName[] = L"StudioCaptureFloatingBar";
const int kBarWidth = 320;
const int kBarHeight = 44;

// Button Hit Regions (X-coordinates relative to bar)
// [ 0..85 ] Timer + Status
// [ 90..135 ] Pause/Resume
// [ 140..185 ] Mic Mute/Unmute
// [ 190..245 ] Video On/Off
// [ 250..310 ] Stop
const int kPauseBtnLeft = 90;
const int kPauseBtnRight = 135;
const int kMuteBtnLeft = 140;
const int kMuteBtnRight = 185;
const int kVideoBtnLeft = 190;
const int kVideoBtnRight = 245;
const int kStopBtnLeft = 250;
const int kStopBtnRight = 310;
}

FloatingBar& FloatingBar::Instance() {
  static FloatingBar instance;
  return instance;
}

FloatingBar::FloatingBar() {
  font_ = CreateFontW(14, 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
                      DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                      CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_SWISS, L"Segoe UI");
}

FloatingBar::~FloatingBar() {
  Hide();
  if (font_) {
    DeleteObject(font_);
    font_ = nullptr;
  }
}

void FloatingBar::Show(HWND main_hwnd,
                       ActionCallback on_pause,
                       ActionCallback on_resume,
                       ActionCallback on_toggle_mute,
                       ActionCallback on_toggle_video,
                       ActionCallback on_stop) {
  main_hwnd_ = main_hwnd;
  on_pause_ = std::move(on_pause);
  on_resume_ = std::move(on_resume);
  on_toggle_mute_ = std::move(on_toggle_mute);
  on_toggle_video_ = std::move(on_toggle_video);
  on_stop_ = std::move(on_stop);
  is_paused_ = false;
  is_muted_ = false;
  is_video_enabled_ = true;
  elapsed_seconds_ = 0;

  if (hwnd_) {
    ShowWindow(hwnd_, SW_SHOWNOACTIVATE);
    return;
  }

  HINSTANCE hinst = GetModuleHandle(nullptr);
  WNDCLASSEXW wc = {sizeof(WNDCLASSEXW)};
  wc.style = CS_HREDRAW | CS_VREDRAW;
  wc.lpfnWndProc = FloatingBar::WndProc;
  wc.hInstance = hinst;
  wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
  wc.hbrBackground = nullptr;
  wc.lpszClassName = kClassName;
  RegisterClassExW(&wc);

  // Position at top center of primary monitor
  int screen_w = GetSystemMetrics(SM_CXSCREEN);
  int x = (screen_w - kBarWidth) / 2;
  int y = 24;

  hwnd_ = CreateWindowExW(
      WS_EX_TOPMOST | WS_EX_TOOLWINDOW,
      kClassName, L"Studio Capture Control",
      WS_POPUP | WS_VISIBLE,
      x, y, kBarWidth, kBarHeight,
      nullptr, nullptr, hinst, this);

  if (hwnd_) {
    SetWindowDisplayAffinity(hwnd_, 0x00000011 /* WDA_EXCLUDEFROMCAPTURE */);
    HRGN rgn = CreateRoundRectRgn(0, 0, kBarWidth, kBarHeight, 22, 22);
    SetWindowRgn(hwnd_, rgn, TRUE);
    ShowWindow(hwnd_, SW_SHOWNOACTIVATE);
    UpdateWindow(hwnd_);
  }
}

void FloatingBar::Hide() {
  if (hwnd_) {
    DestroyWindow(hwnd_);
    hwnd_ = nullptr;
  }
}

void FloatingBar::UpdateState(bool is_paused, bool is_muted, bool is_video_enabled, int elapsed_seconds) {
  is_paused_ = is_paused;
  is_muted_ = is_muted;
  is_video_enabled_ = is_video_enabled;
  elapsed_seconds_ = elapsed_seconds;
  if (hwnd_) {
    InvalidateRect(hwnd_, nullptr, FALSE);
  }
}

LRESULT CALLBACK FloatingBar::WndProc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam) {
  FloatingBar* self = nullptr;
  if (msg == WM_NCCREATE) {
    auto cs = reinterpret_cast<CREATESTRUCTW*>(lparam);
    self = reinterpret_cast<FloatingBar*>(cs->lpCreateParams);
    SetWindowLongPtr(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
  } else {
    self = reinterpret_cast<FloatingBar*>(GetWindowLongPtr(hwnd, GWLP_USERDATA));
  }

  switch (msg) {
    case WM_PAINT:
      if (self) self->OnPaint(hwnd);
      return 0;

    case WM_NCHITTEST: {
      LRESULT hit = DefWindowProcW(hwnd, msg, wparam, lparam);
      if (hit == HTCLIENT) {
        POINT pt = {LOWORD(lparam), HIWORD(lparam)};
        ScreenToClient(hwnd, &pt);
        // If clicking outside button zones, allow window dragging
        if (pt.x < kPauseBtnLeft) {
          return HTCAPTION;
        }
      }
      return hit;
    }

    case WM_LBUTTONDOWN:
      if (self) {
        int x = LOWORD(lparam);
        int y = HIWORD(lparam);
        self->OnLButtonDown(hwnd, x, y);
      }
      return 0;

    case WM_DESTROY:
      if (self) self->hwnd_ = nullptr;
      return 0;

    default:
      return DefWindowProcW(hwnd, msg, wparam, lparam);
  }
}

void FloatingBar::OnPaint(HWND hwnd) {
  PAINTSTRUCT ps;
  HDC hdc = BeginPaint(hwnd, &ps);

  RECT client;
  GetClientRect(hwnd, &client);

  HDC mem_dc = CreateCompatibleDC(hdc);
  HBITMAP mem_bm = CreateCompatibleBitmap(hdc, client.right, client.bottom);
  HBITMAP old_bm = reinterpret_cast<HBITMAP>(SelectObject(mem_dc, mem_bm));

  // Background: dark slate #0F172A
  HBRUSH bg_brush = CreateSolidBrush(RGB(15, 23, 42));
  FillRect(mem_dc, &client, bg_brush);
  DeleteObject(bg_brush);

  // Border: #334155
  HPEN border_pen = CreatePen(PS_SOLID, 1, RGB(51, 65, 85));
  HPEN old_pen = reinterpret_cast<HPEN>(SelectObject(mem_dc, border_pen));
  HBRUSH null_brush = reinterpret_cast<HBRUSH>(GetStockObject(NULL_BRUSH));
  HBRUSH old_brush = reinterpret_cast<HBRUSH>(SelectObject(mem_dc, null_brush));
  RoundRect(mem_dc, 0, 0, client.right, client.bottom, 22, 22);

  SelectObject(mem_dc, old_pen);
  DeleteObject(border_pen);

  // Status Indicator Dot: Red when recording, Amber when paused
  COLORREF dot_color = is_paused_ ? RGB(245, 158, 11) : RGB(239, 68, 68);
  HBRUSH dot_brush = CreateSolidBrush(dot_color);
  HPEN dot_pen = CreatePen(PS_SOLID, 1, dot_color);
  SelectObject(mem_dc, dot_brush);
  SelectObject(mem_dc, dot_pen);
  Ellipse(mem_dc, 14, 18, 22, 26);
  SelectObject(mem_dc, old_brush);
  SelectObject(mem_dc, old_pen);
  DeleteObject(dot_brush);
  DeleteObject(dot_pen);

  // Timer Text: MM:SS
  wchar_t time_str[32];
  int m = elapsed_seconds_ / 60;
  int s = elapsed_seconds_ % 60;
  swprintf_s(time_str, L"%02d:%02d", m, s);

  SetBkMode(mem_dc, TRANSPARENT);
  SetTextColor(mem_dc, RGB(248, 250, 252));
  HFONT old_font = reinterpret_cast<HFONT>(SelectObject(mem_dc, font_));

  RECT timer_rect = {28, 12, 90, 32};
  DrawTextW(mem_dc, time_str, -1, &timer_rect, DT_LEFT | DT_VCENTER | DT_SINGLELINE);

  // Button 1: Pause / Resume
  RECT pause_rect = {kPauseBtnLeft, 7, kPauseBtnRight, 37};
  HBRUSH btn_bg = CreateSolidBrush(RGB(30, 41, 59));
  SelectObject(mem_dc, btn_bg);
  RoundRect(mem_dc, pause_rect.left, pause_rect.top, pause_rect.right, pause_rect.bottom, 10, 10);
  DeleteObject(btn_bg);

  SetTextColor(mem_dc, is_paused_ ? RGB(245, 158, 11) : RGB(203, 213, 225));
  DrawTextW(mem_dc, is_paused_ ? L"▶" : L"❚❚", -1, &pause_rect,
            DT_CENTER | DT_VCENTER | DT_SINGLELINE);

  // Button 2: Mic Mute / Unmute
  RECT mute_rect = {kMuteBtnLeft, 7, kMuteBtnRight, 37};
  btn_bg = CreateSolidBrush(RGB(30, 41, 59));
  SelectObject(mem_dc, btn_bg);
  RoundRect(mem_dc, mute_rect.left, mute_rect.top, mute_rect.right, mute_rect.bottom, 10, 10);
  DeleteObject(btn_bg);

  SetTextColor(mem_dc, is_muted_ ? RGB(239, 68, 68) : RGB(203, 213, 225));
  DrawTextW(mem_dc, is_muted_ ? L"✕Mic" : L"Mic", -1, &mute_rect,
            DT_CENTER | DT_VCENTER | DT_SINGLELINE);

  // Button 3: Video On / Off
  RECT video_rect = {kVideoBtnLeft, 7, kVideoBtnRight, 37};
  btn_bg = CreateSolidBrush(RGB(30, 41, 59));
  SelectObject(mem_dc, btn_bg);
  RoundRect(mem_dc, video_rect.left, video_rect.top, video_rect.right, video_rect.bottom, 10, 10);
  DeleteObject(btn_bg);

  SetTextColor(mem_dc, is_video_enabled_ ? RGB(203, 213, 225) : RGB(239, 68, 68));
  DrawTextW(mem_dc, is_video_enabled_ ? L"Cam" : L"✕Cam", -1, &video_rect,
            DT_CENTER | DT_VCENTER | DT_SINGLELINE);

  // Button 4: Stop (Red pill)
  RECT stop_rect = {kStopBtnLeft, 7, kStopBtnRight, 37};
  HBRUSH stop_bg = CreateSolidBrush(RGB(220, 38, 38));
  SelectObject(mem_dc, stop_bg);
  RoundRect(mem_dc, stop_rect.left, stop_rect.top, stop_rect.right, stop_rect.bottom, 10, 10);
  DeleteObject(stop_bg);

  SetTextColor(mem_dc, RGB(255, 255, 255));
  DrawTextW(mem_dc, L"■ Stop", -1, &stop_rect,
            DT_CENTER | DT_VCENTER | DT_SINGLELINE);

  BitBlt(hdc, 0, 0, client.right, client.bottom, mem_dc, 0, 0, SRCCOPY);

  SelectObject(mem_dc, old_font);
  SelectObject(mem_dc, old_bm);
  DeleteObject(mem_bm);
  DeleteDC(mem_dc);

  EndPaint(hwnd, &ps);
}

void FloatingBar::OnLButtonDown(HWND hwnd, int x, int y) {
  (void)hwnd;
  if (x >= kPauseBtnLeft && x <= kPauseBtnRight) {
    if (is_paused_) {
      if (on_resume_) on_resume_();
    } else {
      if (on_pause_) on_pause_();
    }
  } else if (x >= kMuteBtnLeft && x <= kMuteBtnRight) {
    if (on_toggle_mute_) on_toggle_mute_();
  } else if (x >= kVideoBtnLeft && x <= kVideoBtnRight) {
    if (on_toggle_video_) on_toggle_video_();
  } else if (x >= kStopBtnLeft && x <= kStopBtnRight) {
    if (on_stop_) on_stop_();
  }
}
