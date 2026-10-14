#ifndef RUNNER_FLOATING_BAR_H_
#define RUNNER_FLOATING_BAR_H_

#include <windows.h>
#include <functional>
#include <string>

class FloatingBar {
 public:
  using ActionCallback = std::function<void()>;

  static FloatingBar& Instance();

  void Show(HWND main_hwnd,
            ActionCallback on_pause,
            ActionCallback on_resume,
            ActionCallback on_toggle_mute,
            ActionCallback on_toggle_video,
            ActionCallback on_stop);

  void Hide();
  void UpdateState(bool is_paused, bool is_muted, bool is_video_enabled, int elapsed_seconds);
  bool IsVisible() const { return hwnd_ != nullptr; }

 private:
  FloatingBar();
  ~FloatingBar();

  static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam);
  void OnPaint(HWND hwnd);
  void OnLButtonDown(HWND hwnd, int x, int y);

  HWND hwnd_{nullptr};
  HWND main_hwnd_{nullptr};
  bool is_paused_{false};
  bool is_muted_{false};
  bool is_video_enabled_{true};
  int elapsed_seconds_{0};

  ActionCallback on_pause_;
  ActionCallback on_resume_;
  ActionCallback on_toggle_mute_;
  ActionCallback on_toggle_video_;
  ActionCallback on_stop_;

  HFONT font_{nullptr};
};

#endif  // RUNNER_FLOATING_BAR_H_
