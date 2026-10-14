#include "screen_recording_plugin.h"
#include "screen_recorder.h"
#include "floating_bar.h"

#include <shlobj.h>
#include <wincrypt.h>
#include <ctime>
#include <fstream>
#include <iostream>
#include <vector>

#pragma comment(lib, "crypt32.lib")

namespace {

ScreenRecordingPlugin* g_plugin_instance = nullptr;

std::string GetStringValue(const flutter::EncodableMap& map, const std::string& key, const std::string& default_val = "") {
  auto it = map.find(flutter::EncodableValue(key));
  if (it != map.end() && std::holds_alternative<std::string>(it->second)) {
    return std::get<std::string>(it->second);
  }
  return default_val;
}

bool GetBoolValue(const flutter::EncodableMap& map, const std::string& key, bool default_val = false) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it != map.end() && std::holds_alternative<bool>(it->second)) {
    return std::get<bool>(it->second);
  }
  return default_val;
}

int GetIntValue(const flutter::EncodableMap& map, const std::string& key, int default_val = 0) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it != map.end()) {
    if (std::holds_alternative<int32_t>(it->second)) {
      return std::get<int32_t>(it->second);
    } else if (std::holds_alternative<int64_t>(it->second)) {
      return static_cast<int>(std::get<int64_t>(it->second));
    } else if (std::holds_alternative<double>(it->second)) {
      return static_cast<int>(std::get<double>(it->second));
    }
  }
  return default_val;
}

double GetDoubleValue(const flutter::EncodableMap& map, const std::string& key, double default_val = 0.0) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it != map.end()) {
    if (std::holds_alternative<double>(it->second)) {
      return std::get<double>(it->second);
    } else if (std::holds_alternative<int32_t>(it->second)) {
      return static_cast<double>(std::get<int32_t>(it->second));
    } else if (std::holds_alternative<int64_t>(it->second)) {
      return static_cast<double>(std::get<int64_t>(it->second));
    }
  }
  return default_val;
}

std::wstring Utf8ToWide(const std::string& str) {
  if (str.empty()) return L"";
  int count = MultiByteToWideChar(CP_UTF8, 0, str.c_str(), -1, nullptr, 0);
  std::wstring wide(count, 0);
  MultiByteToWideChar(CP_UTF8, 0, str.c_str(), -1, &wide[0], count);
  if (!wide.empty() && wide.back() == 0) wide.pop_back();
  return wide;
}

std::wstring GetDefaultVideosFolder() {
  wchar_t path[MAX_PATH];
  if (SUCCEEDED(SHGetFolderPathW(nullptr, CSIDL_MYVIDEO, nullptr, 0, path))) {
    std::wstring folder = std::wstring(path) + L"\\Studio Capture";
    SHCreateDirectoryExW(nullptr, folder.c_str(), nullptr);
    return folder;
  }
  return L"";
}

std::string DpapiEncryptString(const std::string& plain_text) {
  if (plain_text.empty()) return "";
  DATA_BLOB in_blob;
  in_blob.pbData = reinterpret_cast<BYTE*>(const_cast<char*>(plain_text.data()));
  in_blob.cbData = static_cast<DWORD>(plain_text.size());

  DATA_BLOB out_blob = {0};
  if (!CryptProtectData(&in_blob, L"StudioCaptureAuth", nullptr, nullptr, nullptr, 0, &out_blob)) {
    return "";
  }

  DWORD b64_len = 0;
  CryptBinaryToStringA(out_blob.pbData, out_blob.cbData, CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF, nullptr, &b64_len);
  std::string b64(b64_len, '\0');
  CryptBinaryToStringA(out_blob.pbData, out_blob.cbData, CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF, &b64[0], &b64_len);
  LocalFree(out_blob.pbData);

  while (!b64.empty() && (b64.back() == '\0' || b64.back() == '\r' || b64.back() == '\n')) {
    b64.pop_back();
  }
  return b64;
}

std::string DpapiDecryptString(const std::string& b64_cipher) {
  if (b64_cipher.empty()) return "";
  DWORD bin_len = 0;
  if (!CryptStringToBinaryA(b64_cipher.c_str(), 0, CRYPT_STRING_BASE64, nullptr, &bin_len, nullptr, nullptr)) {
    return "";
  }
  std::vector<BYTE> cipher_bytes(bin_len);
  if (!CryptStringToBinaryA(b64_cipher.c_str(), 0, CRYPT_STRING_BASE64, cipher_bytes.data(), &bin_len, nullptr, nullptr)) {
    return "";
  }

  DATA_BLOB in_blob;
  in_blob.pbData = cipher_bytes.data();
  in_blob.cbData = bin_len;

  DATA_BLOB out_blob = {0};
  if (!CryptUnprotectData(&in_blob, nullptr, nullptr, nullptr, nullptr, 0, &out_blob)) {
    return "";
  }

  std::string plain(reinterpret_cast<char*>(out_blob.pbData), out_blob.cbData);
  LocalFree(out_blob.pbData);
  return plain;
}

}  // namespace

void ScreenRecordingPlugin::Register(flutter::BinaryMessenger* messenger, HWND main_hwnd) {
  g_plugin_instance = new ScreenRecordingPlugin(messenger, main_hwnd);
}

ScreenRecordingPlugin* ScreenRecordingPlugin::GetInstance() {
  return g_plugin_instance;
}

ScreenRecordingPlugin::ScreenRecordingPlugin(flutter::BinaryMessenger* messenger, HWND main_hwnd)
    : messenger_(messenger), main_hwnd_(main_hwnd) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger_, "screen_recording",
      &flutter::StandardMethodCodec::GetInstance());

  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        HandleMethodCall(call, std::move(result));
      });

  RegisterHotKeys();
}

ScreenRecordingPlugin::~ScreenRecordingPlugin() {
  UnregisterHotKeys();
  FloatingBar::Instance().Hide();
  if (g_plugin_instance == this) {
    g_plugin_instance = nullptr;
  }
}

void ScreenRecordingPlugin::RegisterHotKeys() {
  if (!main_hwnd_) return;
  // Ctrl + Shift + R : Start / Stop
  RegisterHotKey(main_hwnd_, kHotKeyStartStop, MOD_CONTROL | MOD_SHIFT, 'R');
  // Ctrl + Shift + P : Pause / Resume
  RegisterHotKey(main_hwnd_, kHotKeyPauseResume, MOD_CONTROL | MOD_SHIFT, 'P');
}

void ScreenRecordingPlugin::UnregisterHotKeys() {
  if (!main_hwnd_) return;
  UnregisterHotKey(main_hwnd_, kHotKeyStartStop);
  UnregisterHotKey(main_hwnd_, kHotKeyPauseResume);
}

void ScreenRecordingPlugin::HandleHotKey(int hotkey_id) {
  auto& recorder = ScreenRecorder::Instance();
  if (hotkey_id == kHotKeyStartStop) {
    if (recorder.IsRecording()) {
      StopRecording();
    }
  } else if (hotkey_id == kHotKeyPauseResume) {
    if (recorder.IsRecording()) {
      if (recorder.IsPaused()) {
        ResumeRecording();
      } else {
        PauseRecording();
      }
    }
  }
}

void ScreenRecordingPlugin::PauseRecording() {
  auto& recorder = ScreenRecorder::Instance();
  if (recorder.Pause()) {
    FloatingBar::Instance().UpdateState(true, recorder.IsAudioMuted(), recorder.IsVideoEnabled(), recorder.GetElapsedSeconds());
    NotifyStateChanged();
  }
}

void ScreenRecordingPlugin::ResumeRecording() {
  auto& recorder = ScreenRecorder::Instance();
  if (recorder.Resume()) {
    FloatingBar::Instance().UpdateState(false, recorder.IsAudioMuted(), recorder.IsVideoEnabled(), recorder.GetElapsedSeconds());
    NotifyStateChanged();
  }
}

void ScreenRecordingPlugin::ToggleMicMute() {
  auto& recorder = ScreenRecorder::Instance();
  bool new_muted = !recorder.IsAudioMuted();
  recorder.SetAudioMuted(new_muted);
  FloatingBar::Instance().UpdateState(recorder.IsPaused(), new_muted, recorder.IsVideoEnabled(), recorder.GetElapsedSeconds());
  NotifyStateChanged();
}

void ScreenRecordingPlugin::ToggleVideoEnabled() {
  auto& recorder = ScreenRecorder::Instance();
  bool new_enabled = !recorder.IsVideoEnabled();
  recorder.SetVideoEnabled(new_enabled);
  FloatingBar::Instance().UpdateState(recorder.IsPaused(), recorder.IsAudioMuted(), new_enabled, recorder.GetElapsedSeconds());
  NotifyStateChanged();
}

void ScreenRecordingPlugin::StopRecording() {
  auto& recorder = ScreenRecorder::Instance();
  if (!recorder.IsRecording()) return;

  std::string saved_path = recorder.Stop();

  FloatingBar::Instance().Hide();
  RemoveTrayIcon();
  ShowNotification("Studio Capture", "Recording saved to Videos\\Studio Capture");

  // Restore main window so user sees Review screen
  if (main_hwnd_) {
    SetWindowDisplayAffinity(main_hwnd_, WDA_NONE);
    ShowWindow(main_hwnd_, SW_RESTORE);
    SetForegroundWindow(main_hwnd_);
  }

  NotifyStateChanged();
}

void ScreenRecordingPlugin::ShowTrayIcon() {
  if (!main_hwnd_) return;
  NOTIFYICONDATAW nid = {};
  nid.cbSize = sizeof(nid);
  nid.hWnd = main_hwnd_;
  nid.uID = kTrayIconId;
  nid.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  nid.uCallbackMessage = kTrayCallbackMsg;
  nid.hIcon = LoadIcon(nullptr, IDI_APPLICATION);
  wcscpy_s(nid.szTip, L"Studio Capture - Recording (Click to Stop)");
  Shell_NotifyIconW(NIM_ADD, &nid);
  has_tray_icon_ = true;
}

void ScreenRecordingPlugin::RemoveTrayIcon() {
  if (!main_hwnd_ || !has_tray_icon_) return;
  NOTIFYICONDATAW nid = {};
  nid.cbSize = sizeof(nid);
  nid.hWnd = main_hwnd_;
  nid.uID = kTrayIconId;
  Shell_NotifyIconW(NIM_DELETE, &nid);
  has_tray_icon_ = false;
}

void ScreenRecordingPlugin::HandleTrayMessage(WPARAM wparam, LPARAM lparam) {
  (void)wparam;
  if (lparam == WM_LBUTTONUP || lparam == WM_RBUTTONUP) {
    auto& recorder = ScreenRecorder::Instance();
    if (recorder.IsRecording()) {
      StopRecording();
    }
  }
}

void ScreenRecordingPlugin::ShowNotification(const std::string& title, const std::string& message) {
  if (!main_hwnd_) return;
  NOTIFYICONDATAW nid = {};
  nid.cbSize = sizeof(nid);
  nid.hWnd = main_hwnd_;
  nid.uID = 1002;
  nid.uFlags = NIF_INFO | NIF_ICON;
  nid.hIcon = LoadIcon(nullptr, IDI_APPLICATION);
  nid.dwInfoFlags = NIIF_INFO;
  std::wstring w_title = Utf8ToWide(title);
  std::wstring w_msg = Utf8ToWide(message);
  wcsncpy_s(nid.szInfoTitle, sizeof(nid.szInfoTitle) / sizeof(WCHAR), w_title.c_str(), _TRUNCATE);
  wcsncpy_s(nid.szInfo, sizeof(nid.szInfo) / sizeof(WCHAR), w_msg.c_str(), _TRUNCATE);
  Shell_NotifyIconW(NIM_ADD, &nid);
}

void ScreenRecordingPlugin::NotifyStateChanged() {
  if (!channel_) return;
  auto& recorder = ScreenRecorder::Instance();

  flutter::EncodableMap map;
  map[flutter::EncodableValue("isRecording")] = flutter::EncodableValue(recorder.IsRecording());
  map[flutter::EncodableValue("isPaused")] = flutter::EncodableValue(recorder.IsPaused());
  map[flutter::EncodableValue("isAudioMuted")] = flutter::EncodableValue(recorder.IsAudioMuted());
  map[flutter::EncodableValue("isVideoEnabled")] = flutter::EncodableValue(recorder.IsVideoEnabled());
  map[flutter::EncodableValue("showFacecam")] = flutter::EncodableValue(false);
  map[flutter::EncodableValue("lastRecordingPath")] = flutter::EncodableValue(recorder.GetLastRecordingPath());

  channel_->InvokeMethod("onRecordingStateChanged",
                         std::make_unique<flutter::EncodableValue>(map));
}

void ScreenRecordingPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();
  auto& recorder = ScreenRecorder::Instance();

  if (method == "requestPermission") {
    // Windows desktop does not require Android MediaProjection prompt
    result->Success(flutter::EncodableValue(true));
  } else if (method == "getSources") {
    // Return available monitors and open application windows
    auto sources = recorder.GetAvailableSources();
    flutter::EncodableList list;
    for (const auto& s : sources) {
      flutter::EncodableMap item;
      item[flutter::EncodableValue("id")] = flutter::EncodableValue(s.id);
      item[flutter::EncodableValue("title")] = flutter::EncodableValue(s.title);
      item[flutter::EncodableValue("type")] = flutter::EncodableValue(s.type);
      item[flutter::EncodableValue("isPrimary")] = flutter::EncodableValue(s.is_primary);
      item[flutter::EncodableValue("width")] = flutter::EncodableValue(s.width);
      item[flutter::EncodableValue("height")] = flutter::EncodableValue(s.height);
      list.push_back(flutter::EncodableValue(item));
    }
    result->Success(flutter::EncodableValue(list));
  } else if (method == "startRecording") {
    RecordingConfig config;
    if (call.arguments() && std::holds_alternative<flutter::EncodableMap>(*call.arguments())) {
      const auto& args = std::get<flutter::EncodableMap>(*call.arguments());
      config.resolution = GetStringValue(args, "resolution", "1080p");
      config.fps = GetIntValue(args, "fps", 30);
      config.bitrate_mbps = GetDoubleValue(args, "bitrate", 16.0);
      config.orientation = GetStringValue(args, "orientation", "Auto");
      config.audio_source = GetStringValue(args, "audioSource", "Internal + Mic");
      config.source_id = GetStringValue(args, "sourceId", "");
      config.output_path = GetStringValue(args, "outputPath", "");
      config.enable_audio = GetBoolValue(args, "enableAudio", true);
      config.enable_video = GetBoolValue(args, "enableVideo", true);
      config.show_facecam = GetBoolValue(args, "showFacecam", false);
    }

    std::string err;
    if (recorder.Start(config, err)) {
      // Show always-on-top floating control bar
      FloatingBar::Instance().Show(
          main_hwnd_,
          [this]() { PauseRecording(); },
          [this]() { ResumeRecording(); },
          [this]() { ToggleMicMute(); },
          [this]() { ToggleVideoEnabled(); },
          [this]() { StopRecording(); });

      ShowTrayIcon();
      ShowNotification("Studio Capture", "Recording started. Press Ctrl+Shift+R to stop.");

      // Hide this app's own window from capture unless user explicitly chose to record it
      if (main_hwnd_) {
        std::string chosen_win = "window:" + std::to_string(reinterpret_cast<uintptr_t>(main_hwnd_));
        if (config.source_id != chosen_win) {
          SetWindowDisplayAffinity(main_hwnd_, 0x00000011 /* WDA_EXCLUDEFROMCAPTURE */);
          ShowWindow(main_hwnd_, SW_MINIMIZE);
        }
      }

      NotifyStateChanged();
      result->Success(flutter::EncodableValue(true));
    } else {
      result->Error("START_FAILED", err);
    }
  } else if (method == "pauseRecording") {
    PauseRecording();
    result->Success(flutter::EncodableValue(true));
  } else if (method == "resumeRecording") {
    ResumeRecording();
    result->Success(flutter::EncodableValue(true));
  } else if (method == "stopRecording") {
    std::string saved_path = recorder.Stop();
    FloatingBar::Instance().Hide();

    if (main_hwnd_) {
      SetWindowDisplayAffinity(main_hwnd_, WDA_NONE);
      ShowWindow(main_hwnd_, SW_RESTORE);
      SetForegroundWindow(main_hwnd_);
    }

    NotifyStateChanged();
    result->Success(flutter::EncodableValue(saved_path));
  } else if (method == "getRecordingStatus") {
    flutter::EncodableMap map;
    map[flutter::EncodableValue("isRecording")] = flutter::EncodableValue(recorder.IsRecording());
    map[flutter::EncodableValue("isPaused")] = flutter::EncodableValue(recorder.IsPaused());
    map[flutter::EncodableValue("isAudioMuted")] = flutter::EncodableValue(recorder.IsAudioMuted());
    map[flutter::EncodableValue("isVideoEnabled")] = flutter::EncodableValue(recorder.IsVideoEnabled());
    map[flutter::EncodableValue("lastRecordingPath")] = flutter::EncodableValue(recorder.GetLastRecordingPath());
    map[flutter::EncodableValue("hasPermission")] = flutter::EncodableValue(true);
    map[flutter::EncodableValue("elapsedSeconds")] = flutter::EncodableValue(recorder.GetElapsedSeconds());
    result->Success(flutter::EncodableValue(map));
  } else if (method == "setVideoEnabled") {
    bool enabled = true;
    if (call.arguments() && std::holds_alternative<bool>(*call.arguments())) {
      enabled = std::get<bool>(*call.arguments());
    }
    recorder.SetVideoEnabled(enabled);
    FloatingBar::Instance().UpdateState(recorder.IsPaused(), recorder.IsAudioMuted(), enabled, recorder.GetElapsedSeconds());
    NotifyStateChanged();
    result->Success(flutter::EncodableValue(true));
  } else if (method == "setAudioMuted") {
    bool muted = false;
    if (call.arguments() && std::holds_alternative<bool>(*call.arguments())) {
      muted = std::get<bool>(*call.arguments());
    }
    recorder.SetAudioMuted(muted);
    FloatingBar::Instance().UpdateState(recorder.IsPaused(), muted, recorder.IsVideoEnabled(), recorder.GetElapsedSeconds());
    NotifyStateChanged();
    result->Success(flutter::EncodableValue(true));
  } else if (method == "setFacecamEnabled") {
    result->Success(flutter::EncodableValue(true));
  } else if (method == "getVideoMetadata") {
    std::string path;
    if (call.arguments() && std::holds_alternative<flutter::EncodableMap>(*call.arguments())) {
      const auto& args = std::get<flutter::EncodableMap>(*call.arguments());
      path = GetStringValue(args, "path", "");
    } else if (call.arguments() && std::holds_alternative<std::string>(*call.arguments())) {
      path = std::get<std::string>(*call.arguments());
    }

    if (path.empty()) path = recorder.GetLastRecordingPath();
    auto meta = ScreenRecorder::GetVideoMetadata(path);

    flutter::EncodableMap map;
    map[flutter::EncodableValue("width")] = flutter::EncodableValue(meta.width);
    map[flutter::EncodableValue("height")] = flutter::EncodableValue(meta.height);
    map[flutter::EncodableValue("duration")] = flutter::EncodableValue(meta.duration_ms);
    map[flutter::EncodableValue("fps")] = flutter::EncodableValue(meta.fps);
    map[flutter::EncodableValue("bitrate")] = flutter::EncodableValue(meta.bitrate_bps);
    map[flutter::EncodableValue("rotation")] = flutter::EncodableValue(0);
    result->Success(flutter::EncodableValue(map));
  } else if (method == "getStorageInfo") {
    int64_t avail = 0, total = 0;
    ScreenRecorder::GetStorageInfo(avail, total);
    flutter::EncodableMap map;
    map[flutter::EncodableValue("availableDeviceBytes")] = flutter::EncodableValue(avail);
    map[flutter::EncodableValue("totalDeviceBytes")] = flutter::EncodableValue(total);
    result->Success(flutter::EncodableValue(map));
  } else if (method == "saveToGallery") {
    result->Success(flutter::EncodableValue(true));
  } else if (method == "saveImageToGallery") {
    result->Success(flutter::EncodableValue(true));
  } else if (method == "playAudioCue") {
    std::string type = "start";
    if (call.arguments() && std::holds_alternative<flutter::EncodableMap>(*call.arguments())) {
      const auto& args = std::get<flutter::EncodableMap>(*call.arguments());
      type = GetStringValue(args, "type", "start");
    }
    if (type == "start") {
      MessageBeep(MB_ICONASTERISK);
    } else if (type == "stop") {
      MessageBeep(MB_OK);
    } else {
      MessageBeep(MB_ICONEXCLAMATION);
    }
    result->Success(flutter::EncodableValue(true));
  } else if (method == "vibrate") {
    result->Success(flutter::EncodableValue(true));
  } else if (method == "minimizeApp") {
    if (main_hwnd_) ShowWindow(main_hwnd_, SW_MINIMIZE);
    result->Success(flutter::EncodableValue(true));
  } else if (method == "restoreApp" || method == "bringToFront") {
    if (main_hwnd_) {
      ShowWindow(main_hwnd_, SW_RESTORE);
      SetForegroundWindow(main_hwnd_);
    }
    result->Success(flutter::EncodableValue(true));
  } else if (method == "showInExplorer" || method == "openFolder") {
    std::string path;
    if (call.arguments() && std::holds_alternative<flutter::EncodableMap>(*call.arguments())) {
      const auto& args = std::get<flutter::EncodableMap>(*call.arguments());
      path = GetStringValue(args, "path", "");
    } else if (call.arguments() && std::holds_alternative<std::string>(*call.arguments())) {
      path = std::get<std::string>(*call.arguments());
    }
    if (!path.empty()) {
      std::wstring w_path = Utf8ToWide(path);
      std::wstring params = L"/select,\"" + w_path + L"\"";
      ShellExecuteW(nullptr, L"open", L"explorer.exe", params.c_str(), nullptr, SW_SHOWNORMAL);
    } else {
      std::wstring folder = GetDefaultVideosFolder();
      ShellExecuteW(nullptr, L"open", folder.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
    }
    result->Success(flutter::EncodableValue(true));
  } else if (method == "openEmailClient") {
    std::string to = "contact@ispcorp.in";
    std::string subject = "Studio Capture Support";
    if (call.arguments() && std::holds_alternative<flutter::EncodableMap>(*call.arguments())) {
      const auto& args = std::get<flutter::EncodableMap>(*call.arguments());
      to = GetStringValue(args, "to", "contact@ispcorp.in");
      subject = GetStringValue(args, "subject", "Studio Capture Support");
    }
    std::wstring mailto = L"mailto:" + Utf8ToWide(to) + L"?subject=" + Utf8ToWide(subject);
    HINSTANCE hInst = ShellExecuteW(nullptr, L"open", mailto.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
    result->Success(flutter::EncodableValue(reinterpret_cast<intptr_t>(hInst) > 32));
  } else if (method == "dpapiEncrypt") {
    std::string text;
    if (call.arguments() && std::holds_alternative<flutter::EncodableMap>(*call.arguments())) {
      const auto& args = std::get<flutter::EncodableMap>(*call.arguments());
      text = GetStringValue(args, "data", "");
    } else if (call.arguments() && std::holds_alternative<std::string>(*call.arguments())) {
      text = std::get<std::string>(*call.arguments());
    }
    std::string encrypted = DpapiEncryptString(text);
    result->Success(flutter::EncodableValue(encrypted));
  } else if (method == "dpapiDecrypt") {
    std::string cipher;
    if (call.arguments() && std::holds_alternative<flutter::EncodableMap>(*call.arguments())) {
      const auto& args = std::get<flutter::EncodableMap>(*call.arguments());
      cipher = GetStringValue(args, "data", "");
    } else if (call.arguments() && std::holds_alternative<std::string>(*call.arguments())) {
      cipher = std::get<std::string>(*call.arguments());
    }
    std::string decrypted = DpapiDecryptString(cipher);
    result->Success(flutter::EncodableValue(decrypted));
  } else if (method == "trimVideo" || method == "transcodeVideo") {
    std::string in_path, out_path;
    if (call.arguments() && std::holds_alternative<flutter::EncodableMap>(*call.arguments())) {
      const auto& args = std::get<flutter::EncodableMap>(*call.arguments());
      in_path = GetStringValue(args, "inputPath", "");
      out_path = GetStringValue(args, "outputPath", "");
    }
    bool success = false;
    if (!in_path.empty() && !out_path.empty()) {
      if (in_path == out_path) {
        success = true;
      } else {
        std::wstring w_in = Utf8ToWide(in_path);
        std::wstring w_out = Utf8ToWide(out_path);
        success = (CopyFileW(w_in.c_str(), w_out.c_str(), FALSE) != 0);
      }
    }
    result->Success(flutter::EncodableValue(success));
  } else if (method == "areNotificationsEnabled" ||
             method == "requestNotificationPermission") {
    result->Success(flutter::EncodableValue(true));
  } else if (method == "openNotificationSettings") {
    ShellExecuteW(nullptr, L"open", L"ms-settings:notifications", nullptr, nullptr, SW_SHOWNORMAL);
    result->Success(flutter::EncodableValue(true));
  } else if (method == "showSystemNotification") {
    std::string title = "Studio Capture";
    std::string message = "";
    if (call.arguments() && std::holds_alternative<flutter::EncodableMap>(*call.arguments())) {
      const auto& args = std::get<flutter::EncodableMap>(*call.arguments());
      title = GetStringValue(args, "title", "Studio Capture");
      message = GetStringValue(args, "message", "");
    }
    ShowNotification(title, message);
    result->Success(flutter::EncodableValue(true));
  } else if (method == "cancelNotification") {
    if (main_hwnd_) {
      NOTIFYICONDATAW nid = {};
      nid.cbSize = sizeof(nid);
      nid.hWnd = main_hwnd_;
      nid.uID = 1002;
      Shell_NotifyIconW(NIM_DELETE, &nid);
    }
    result->Success(flutter::EncodableValue(true));
  } else if (method == "setConfig") {
    result->Success(flutter::EncodableValue(true));
  } else if (method == "isWifiConnected") {
    result->Success(flutter::EncodableValue(true));
  } else {
    result->NotImplemented();
  }
}
