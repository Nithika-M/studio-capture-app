#ifndef RUNNER_SCREEN_RECORDING_PLUGIN_H_
#define RUNNER_SCREEN_RECORDING_PLUGIN_H_

#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <memory>

class ScreenRecordingPlugin {
 public:
  static void Register(flutter::BinaryMessenger* messenger, HWND main_hwnd);
  static ScreenRecordingPlugin* GetInstance();

  ScreenRecordingPlugin(flutter::BinaryMessenger* messenger, HWND main_hwnd);
  ~ScreenRecordingPlugin();

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void HandleHotKey(int hotkey_id);
  void NotifyStateChanged();

  // Actions called from Hotkeys or Floating Control Bar
  void PauseRecording();
  void ResumeRecording();
  void ToggleMicMute();
  void ToggleVideoEnabled();
  void StopRecording();

  void HandleTrayMessage(WPARAM wparam, LPARAM lparam);
  void ShowNotification(const std::string& title, const std::string& message);
  void ShowTrayIcon();
  void RemoveTrayIcon();

 private:
  flutter::BinaryMessenger* messenger_{nullptr};
  HWND main_hwnd_{nullptr};
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  bool has_tray_icon_{false};

  // Global Hotkey & Tray IDs
  static constexpr int kHotKeyStartStop = 101;
  static constexpr int kHotKeyPauseResume = 102;
  static constexpr UINT kTrayCallbackMsg = WM_APP + 101;
  static constexpr UINT kTrayIconId = 1001;

  void RegisterHotKeys();
  void UnregisterHotKeys();
};

#endif  // RUNNER_SCREEN_RECORDING_PLUGIN_H_
