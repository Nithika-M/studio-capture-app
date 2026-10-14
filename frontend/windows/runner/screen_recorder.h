#ifndef RUNNER_SCREEN_RECORDER_H_
#define RUNNER_SCREEN_RECORDER_H_

#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mferror.h>
#include <d3d11.h>
#include <dxgi1_2.h>
#include <mmdeviceapi.h>
#include <audioclient.h>

#include <atomic>
#include <chrono>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

struct CaptureSourceInfo {
  std::string id;       // e.g. "display:0" or "window:12345"
  std::string title;    // e.g. "Display 1 (1920x1080)" or "Chrome - Google"
  std::string type;     // "screen" or "window"
  bool is_primary{false};
  int width{0};
  int height{0};
  HWND hwnd{nullptr};
};

struct RecordingConfig {
  std::string resolution{"1080p"}; // "4K", "1080p", "720p", "480p"
  int fps{30};
  double bitrate_mbps{16.0};
  std::string orientation{"Auto"};
  std::string audio_source{"Internal + Mic"}; // "Internal", "Microphone", "Internal + Mic", "Mute"
  std::string source_id{""}; // empty = primary screen
  std::string output_path{""};
  bool enable_audio{true};
  bool enable_video{true};
  bool show_facecam{false};
};

struct VideoFileMetadata {
  int width{0};
  int height{0};
  int64_t duration_ms{0};
  double fps{0.0};
  int bitrate_bps{0};
};

class ScreenRecorder {
 public:
  static ScreenRecorder& Instance();

  ScreenRecorder();
  ~ScreenRecorder();

  // Enumerate capture targets (monitors and visible windows)
  std::vector<CaptureSourceInfo> GetAvailableSources();

  // Start recording with specified configuration
  bool Start(const RecordingConfig& config, std::string& error_message);

  // Pause / Resume
  bool Pause();
  bool Resume();

  // Stop recording and return finalized file path
  std::string Stop();

  // State queries
  bool IsRecording() const { return is_recording_.load(); }
  bool IsPaused() const { return is_paused_.load(); }
  bool IsAudioMuted() const { return is_mic_muted_.load(); }
  bool IsVideoEnabled() const { return is_video_enabled_.load(); }
  int GetElapsedSeconds() const;
  std::string GetLastRecordingPath() const { return last_recording_path_; }

  // Dynamic toggles while recording
  void SetAudioMuted(bool muted) { is_mic_muted_.store(muted); }
  void SetVideoEnabled(bool enabled) { is_video_enabled_.store(enabled); }

  // Video metadata extraction using Media Foundation SourceReader
  static VideoFileMetadata GetVideoMetadata(const std::string& file_path);

  // Disk space
  static void GetStorageInfo(int64_t& available_bytes, int64_t& total_bytes);

 private:
  void VideoCaptureLoop();
  void AudioCaptureLoop();

  bool InitD3D();
  void CleanupD3D();

  bool InitDXGIDuplication(int monitor_index);
  void CleanupDXGIDuplication();

  bool InitMediaFoundation(const std::wstring& output_file, int out_w, int out_h, int fps, int bitrate_bps, bool enable_audio);
  void CleanupMediaFoundation();

  bool InitAudioClients();
  void CleanupAudioClients();

  // Frame capture helpers
  bool CaptureDXGIFrame(std::vector<uint8_t>& bgra_buffer, int& frame_w, int& frame_h);
  bool CaptureGDIFrame(HWND hwnd, std::vector<uint8_t>& bgra_buffer, int& frame_w, int& frame_h);
  void ScaleBgra(const uint8_t* src, int src_w, int src_h, uint8_t* dst, int dst_w, int dst_h);

  // State
  std::atomic<bool> is_recording_{false};
  std::atomic<bool> is_paused_{false};
  std::atomic<bool> is_mic_muted_{false};
  std::atomic<bool> is_video_enabled_{true};
  std::atomic<bool> stop_requested_{false};

  RecordingConfig config_;
  int target_width_{1920};
  int target_height_{1080};
  std::string last_recording_path_;

  // Timing
  std::chrono::steady_clock::time_point start_time_;
  std::chrono::steady_clock::time_point pause_start_time_;
  std::chrono::milliseconds total_paused_duration_{0};

  // Threads
  std::thread video_thread_;
  std::thread audio_thread_;

  // D3D11 / DXGI
  ID3D11Device* d3d_device_{nullptr};
  ID3D11DeviceContext* d3d_context_{nullptr};
  IDXGIOutputDuplication* dxgi_duplication_{nullptr};
  ID3D11Texture2D* staging_texture_{nullptr};
  int dup_width_{0};
  int dup_height_{0};

  // Media Foundation
  IMFSinkWriter* sink_writer_{nullptr};
  DWORD video_stream_index_{0};
  DWORD audio_stream_index_{0};
  bool has_audio_stream_{false};
  LONGLONG frame_duration_hns_{333333}; // default 30fps

  // WASAPI Audio
  IMMDeviceEnumerator* mm_device_enumerator_{nullptr};
  IAudioClient* loopback_audio_client_{nullptr};
  IAudioCaptureClient* loopback_capture_client_{nullptr};
  WAVEFORMATEX* loopback_wave_format_{nullptr};

  IAudioClient* mic_audio_client_{nullptr};
  IAudioCaptureClient* mic_capture_client_{nullptr};
  WAVEFORMATEX* mic_wave_format_{nullptr};

  std::mutex sink_mutex_;
};

#endif  // RUNNER_SCREEN_RECORDER_H_
