#include "screen_recorder.h"

#include <shlobj.h>
#include <shlwapi.h>
#include <algorithm>
#include <cmath>
#include <ctime>
#include <iostream>

#pragma comment(lib, "mfplat.lib")
#pragma comment(lib, "mfreadwrite.lib")
#pragma comment(lib, "mfuuid.lib")
#pragma comment(lib, "wmcodecdspuuid.lib")
#pragma comment(lib, "d3d11.lib")
#pragma comment(lib, "dxgi.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "shlwapi.lib")
#pragma comment(lib, "winmm.lib")

namespace {

template <class T>
void SafeRelease(T** ppT) {
  if (ppT && *ppT) {
    (*ppT)->Release();
    *ppT = nullptr;
  }
}

// Convert UTF-8 string to wide string
std::wstring Utf8ToWide(const std::string& str) {
  if (str.empty()) return L"";
  int count = MultiByteToWideChar(CP_UTF8, 0, str.c_str(), -1, nullptr, 0);
  std::wstring wide(count, 0);
  MultiByteToWideChar(CP_UTF8, 0, str.c_str(), -1, &wide[0], count);
  if (!wide.empty() && wide.back() == 0) wide.pop_back();
  return wide;
}

// Convert wide string to UTF-8
std::string WideToUtf8(const std::wstring& wide) {
  if (wide.empty()) return "";
  int count = WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), -1, nullptr, 0, nullptr, nullptr);
  std::string str(count, 0);
  WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), -1, &str[0], count, nullptr, nullptr);
  if (!str.empty() && str.back() == 0) str.pop_back();
  return str;
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

}  // namespace

ScreenRecorder& ScreenRecorder::Instance() {
  static ScreenRecorder instance;
  return instance;
}

ScreenRecorder::ScreenRecorder() {
  CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  MFStartup(MF_VERSION, MFSTARTUP_NOSOCKET);
}

ScreenRecorder::~ScreenRecorder() {
  if (is_recording_) {
    Stop();
  }
  MFShutdown();
}

std::vector<CaptureSourceInfo> ScreenRecorder::GetAvailableSources() {
  std::vector<CaptureSourceInfo> sources;

  // 1. Enumerate Monitors
  struct MonitorEnumData {
    std::vector<CaptureSourceInfo>* list;
    int index;
  } mon_data = {&sources, 0};

  EnumDisplayMonitors(
      nullptr, nullptr,
      [](HMONITOR hmon, HDC, LPRECT, LPARAM lparam) -> BOOL {
        auto data = reinterpret_cast<MonitorEnumData*>(lparam);
        MONITORINFOEXW mi = {sizeof(MONITORINFOEXW)};
        if (GetMonitorInfoW(hmon, &mi)) {
          int w = mi.rcMonitor.right - mi.rcMonitor.left;
          int h = mi.rcMonitor.bottom - mi.rcMonitor.top;
          bool is_pri = (mi.dwFlags & MONITORINFOF_PRIMARY) != 0;

          CaptureSourceInfo info;
          info.id = "display:" + std::to_string(data->index);
          wchar_t title_buf[128];
          swprintf_s(title_buf, L"Display %d (%dx%d)%s", data->index + 1, w, h,
                     is_pri ? L" - Primary" : L"");
          info.title = WideToUtf8(title_buf);
          info.type = "screen";
          info.is_primary = is_pri;
          info.width = w;
          info.height = h;
          info.hwnd = nullptr;
          data->list->push_back(info);
          data->index++;
        }
        return TRUE;
      },
      reinterpret_cast<LPARAM>(&mon_data));

  // 2. Enumerate Top-Level Visible Windows
  EnumWindows(
      [](HWND hwnd, LPARAM lparam) -> BOOL {
        if (!IsWindowVisible(hwnd) || IsIconic(hwnd)) return TRUE;

        // Skip tool windows or empty titles
        LONG_PTR ex_style = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
        if (ex_style & WS_EX_TOOLWINDOW) return TRUE;

        int len = GetWindowTextLengthW(hwnd);
        if (len <= 0) return TRUE;

        RECT r;
        GetWindowRect(hwnd, &r);
        int w = r.right - r.left;
        int h = r.bottom - r.top;
        if (w < 100 || h < 100) return TRUE;

        wchar_t title[256];
        GetWindowTextW(hwnd, title, 256);

        // Filter out Progman, Desktop, Shell, or Studio Capture controls
        if (wcscmp(title, L"Program Manager") == 0 ||
            wcscmp(title, L"Studio Capture Control") == 0) {
          return TRUE;
        }

        auto list = reinterpret_cast<std::vector<CaptureSourceInfo>*>(lparam);
        CaptureSourceInfo info;
        info.id = "window:" + std::to_string(reinterpret_cast<uintptr_t>(hwnd));
        info.title = WideToUtf8(title);
        info.type = "window";
        info.is_primary = false;
        info.width = w;
        info.height = h;
        info.hwnd = hwnd;
        list->push_back(info);
        return TRUE;
      },
      reinterpret_cast<LPARAM>(&sources));

  return sources;
}

bool ScreenRecorder::Start(const RecordingConfig& config, std::string& error_message) {
  if (is_recording_) {
    error_message = "Recording is already in progress";
    return false;
  }

  config_ = config;
  stop_requested_ = false;
  is_paused_ = false;
  is_mic_muted_ = false;
  is_video_enabled_ = config.enable_video;
  total_paused_duration_ = std::chrono::milliseconds(0);

  // Determine Target Resolution
  int w = 1920;
  int h = 1080;
  if (config.resolution == "4K") {
    w = 3840;
    h = 2160;
  } else if (config.resolution == "720p") {
    w = 1280;
    h = 720;
  } else if (config.resolution == "480p") {
    w = 854;
    h = 480;
  }

  if (config.orientation == "Portrait") {
    std::swap(w, h);
  }
  target_width_ = w;
  target_height_ = h;

  int fps = (config.fps > 0) ? config.fps : 30;
  frame_duration_hns_ = 10000000 / fps;
  int bitrate_bps = static_cast<int>(config.bitrate_mbps * 1000000.0);
  if (bitrate_bps <= 0) bitrate_bps = 16000000;

  // Determine Output File Path
  std::wstring output_file;
  if (!config.output_path.empty()) {
    output_file = Utf8ToWide(config.output_path);
  } else {
    std::wstring folder = GetDefaultVideosFolder();
    time_t now = time(nullptr);
    struct tm t;
    localtime_s(&t, &now);
    wchar_t filename[128];
    swprintf_s(filename, L"\\SCR_%04d%02d%02d_%02d%02d%02d.mp4",
               t.tm_year + 1900, t.tm_mon + 1, t.tm_mday,
               t.tm_hour, t.tm_min, t.tm_sec);
    output_file = folder + filename;
  }

  // Ensure output directory exists
  wchar_t dir_buffer[MAX_PATH];
  wcscpy_s(dir_buffer, output_file.c_str());
  PathRemoveFileSpecW(dir_buffer);
  SHCreateDirectoryExW(nullptr, dir_buffer, nullptr);

  last_recording_path_ = WideToUtf8(output_file);

  // Initialize D3D11 & DXGI Desktop Duplication for screen capture
  bool is_window_capture = (config.source_id.rfind("window:", 0) == 0);
  if (!is_window_capture) {
    int mon_index = 0;
    if (config.source_id.rfind("display:", 0) == 0) {
      mon_index = std::atoi(config.source_id.substr(8).c_str());
    }
    if (InitD3D()) {
      InitDXGIDuplication(mon_index);
    }
  }

  // Initialize Media Foundation SinkWriter
  bool enable_audio = config.enable_audio && (config.audio_source != "Mute");
  if (!InitMediaFoundation(output_file, target_width_, target_height_, fps, bitrate_bps, enable_audio)) {
    error_message = "Failed to initialize Windows Media Foundation H.264 MP4 encoder";
    CleanupDXGIDuplication();
    CleanupD3D();
    return false;
  }

  // Initialize WASAPI Audio Clients if audio requested
  if (enable_audio) {
    InitAudioClients();
  }

  // Start Capture Threads
  is_recording_ = true;
  start_time_ = std::chrono::steady_clock::now();

  video_thread_ = std::thread(&ScreenRecorder::VideoCaptureLoop, this);
  if (has_audio_stream_) {
    audio_thread_ = std::thread(&ScreenRecorder::AudioCaptureLoop, this);
  }

  return true;
}

bool ScreenRecorder::Pause() {
  if (!is_recording_ || is_paused_) return false;
  is_paused_ = true;
  pause_start_time_ = std::chrono::steady_clock::now();
  return true;
}

bool ScreenRecorder::Resume() {
  if (!is_recording_ || !is_paused_) return false;
  auto now = std::chrono::steady_clock::now();
  total_paused_duration_ += std::chrono::duration_cast<std::chrono::milliseconds>(now - pause_start_time_);
  is_paused_ = false;
  return true;
}

std::string ScreenRecorder::Stop() {
  if (!is_recording_) return last_recording_path_;

  stop_requested_ = true;
  is_recording_ = false;

  if (video_thread_.joinable()) {
    video_thread_.join();
  }
  if (audio_thread_.joinable()) {
    audio_thread_.join();
  }

  CleanupAudioClients();
  CleanupMediaFoundation();
  CleanupDXGIDuplication();
  CleanupD3D();

  return last_recording_path_;
}

int ScreenRecorder::GetElapsedSeconds() const {
  if (!is_recording_) return 0;
  auto now = is_paused_ ? pause_start_time_ : std::chrono::steady_clock::now();
  auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(now - start_time_) - total_paused_duration_;
  return static_cast<int>(std::max<int64_t>(0, elapsed.count() / 1000));
}

bool ScreenRecorder::InitD3D() {
  CleanupD3D();

  D3D_FEATURE_LEVEL feature_levels[] = {
      D3D_FEATURE_LEVEL_11_1, D3D_FEATURE_LEVEL_11_0,
      D3D_FEATURE_LEVEL_10_1, D3D_FEATURE_LEVEL_10_0};
  D3D_FEATURE_LEVEL feature_level;

  HRESULT hr = D3D11CreateDevice(
      nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr,
      D3D11_CREATE_DEVICE_BGRA_SUPPORT,
      feature_levels, ARRAYSIZE(feature_levels),
      D3D11_SDK_VERSION, &d3d_device_, &feature_level, &d3d_context_);

  if (FAILED(hr)) {
    hr = D3D11CreateDevice(
        nullptr, D3D_DRIVER_TYPE_WARP, nullptr,
        D3D11_CREATE_DEVICE_BGRA_SUPPORT,
        feature_levels, ARRAYSIZE(feature_levels),
        D3D11_SDK_VERSION, &d3d_device_, &feature_level, &d3d_context_);
  }

  return SUCCEEDED(hr);
}

void ScreenRecorder::CleanupD3D() {
  SafeRelease(&staging_texture_);
  SafeRelease(&d3d_context_);
  SafeRelease(&d3d_device_);
}

bool ScreenRecorder::InitDXGIDuplication(int monitor_index) {
  CleanupDXGIDuplication();
  if (!d3d_device_) return false;

  IDXGIDevice* dxgi_device = nullptr;
  if (FAILED(d3d_device_->QueryInterface(__uuidof(IDXGIDevice), (void**)&dxgi_device))) {
    return false;
  }

  IDXGIAdapter* dxgi_adapter = nullptr;
  if (FAILED(dxgi_device->GetAdapter(&dxgi_adapter))) {
    SafeRelease(&dxgi_device);
    return false;
  }
  SafeRelease(&dxgi_device);

  IDXGIOutput* dxgi_output = nullptr;
  if (FAILED(dxgi_adapter->EnumOutputs(static_cast<UINT>(monitor_index), &dxgi_output))) {
    // Fallback to primary output 0
    if (FAILED(dxgi_adapter->EnumOutputs(0, &dxgi_output))) {
      SafeRelease(&dxgi_adapter);
      return false;
    }
  }
  SafeRelease(&dxgi_adapter);

  IDXGIOutput1* dxgi_output1 = nullptr;
  if (FAILED(dxgi_output->QueryInterface(__uuidof(IDXGIOutput1), (void**)&dxgi_output1))) {
    SafeRelease(&dxgi_output);
    return false;
  }
  SafeRelease(&dxgi_output);

  DXGI_OUTPUT_DESC desc;
  dxgi_output1->GetDesc(&desc);
  dup_width_ = desc.DesktopCoordinates.right - desc.DesktopCoordinates.left;
  dup_height_ = desc.DesktopCoordinates.bottom - desc.DesktopCoordinates.top;

  HRESULT hr = dxgi_output1->DuplicateOutput(d3d_device_, &dxgi_duplication_);
  SafeRelease(&dxgi_output1);

  if (FAILED(hr)) {
    dxgi_duplication_ = nullptr;
    return false;
  }

  // Create Staging Texture to read back CPU pixels
  D3D11_TEXTURE2D_DESC tex_desc = {};
  tex_desc.Width = static_cast<UINT>(dup_width_);
  tex_desc.Height = static_cast<UINT>(dup_height_);
  tex_desc.MipLevels = 1;
  tex_desc.ArraySize = 1;
  tex_desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  tex_desc.SampleDesc.Count = 1;
  tex_desc.Usage = D3D11_USAGE_STAGING;
  tex_desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;

  hr = d3d_device_->CreateTexture2D(&tex_desc, nullptr, &staging_texture_);
  return SUCCEEDED(hr);
}

void ScreenRecorder::CleanupDXGIDuplication() {
  SafeRelease(&dxgi_duplication_);
  SafeRelease(&staging_texture_);
}

bool ScreenRecorder::InitMediaFoundation(const std::wstring& output_file,
                                        int out_w, int out_h, int fps,
                                        int bitrate_bps, bool enable_audio) {
  CleanupMediaFoundation();

  IMFAttributes* attributes = nullptr;
  MFCreateAttributes(&attributes, 4);
  attributes->SetUINT32(MF_READWRITE_ENABLE_HARDWARE_TRANSFORMS, TRUE);
  attributes->SetUINT32(MF_SINK_WRITER_DISABLE_THROTTLING, TRUE);
  attributes->SetUINT32(MF_LOW_LATENCY, TRUE);

  HRESULT hr = MFCreateSinkWriterFromURL(output_file.c_str(), nullptr, attributes, &sink_writer_);
  SafeRelease(&attributes);
  if (FAILED(hr)) return false;

  // 1. Configure Target Video Stream (H.264)
  IMFMediaType* video_out_type = nullptr;
  MFCreateMediaType(&video_out_type);
  video_out_type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
  video_out_type->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_H264);
  video_out_type->SetUINT32(MF_MT_AVG_BITRATE, static_cast<UINT32>(bitrate_bps));
  video_out_type->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
  MFSetAttributeSize(video_out_type, MF_MT_FRAME_SIZE, static_cast<UINT32>(out_w), static_cast<UINT32>(out_h));
  MFSetAttributeRatio(video_out_type, MF_MT_FRAME_RATE, static_cast<UINT32>(fps), 1);
  MFSetAttributeRatio(video_out_type, MF_MT_PIXEL_ASPECT_RATIO, 1, 1);

  hr = sink_writer_->AddStream(video_out_type, &video_stream_index_);
  SafeRelease(&video_out_type);
  if (FAILED(hr)) return false;

  // 2. Configure Video Input Stream (RGB32 / BGRA)
  IMFMediaType* video_in_type = nullptr;
  MFCreateMediaType(&video_in_type);
  video_in_type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
  video_in_type->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32);
  video_in_type->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
  MFSetAttributeSize(video_in_type, MF_MT_FRAME_SIZE, static_cast<UINT32>(out_w), static_cast<UINT32>(out_h));
  MFSetAttributeRatio(video_in_type, MF_MT_FRAME_RATE, static_cast<UINT32>(fps), 1);
  MFSetAttributeRatio(video_in_type, MF_MT_PIXEL_ASPECT_RATIO, 1, 1);

  hr = sink_writer_->SetInputMediaType(video_stream_index_, video_in_type, nullptr);
  SafeRelease(&video_in_type);
  if (FAILED(hr)) return false;

  has_audio_stream_ = false;

  // 3. Configure Audio Streams (AAC) if requested
  if (enable_audio) {
    IMFMediaType* audio_out_type = nullptr;
    MFCreateMediaType(&audio_out_type);
    audio_out_type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
    audio_out_type->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_AAC);
    audio_out_type->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
    audio_out_type->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, 48000);
    audio_out_type->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, 2);
    audio_out_type->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, 24000);  // 192 kbps

    hr = sink_writer_->AddStream(audio_out_type, &audio_stream_index_);
    SafeRelease(&audio_out_type);

    if (SUCCEEDED(hr)) {
      IMFMediaType* audio_in_type = nullptr;
      MFCreateMediaType(&audio_in_type);
      audio_in_type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
      audio_in_type->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_PCM);
      audio_in_type->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
      audio_in_type->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, 48000);
      audio_in_type->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, 2);
      audio_in_type->SetUINT32(MF_MT_AUDIO_BLOCK_ALIGNMENT, 4);
      audio_in_type->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, 48000 * 4);

      hr = sink_writer_->SetInputMediaType(audio_stream_index_, audio_in_type, nullptr);
      SafeRelease(&audio_in_type);
      if (SUCCEEDED(hr)) {
        has_audio_stream_ = true;
      }
    }
  }

  hr = sink_writer_->BeginWriting();
  return SUCCEEDED(hr);
}

void ScreenRecorder::CleanupMediaFoundation() {
  std::lock_guard<std::mutex> lock(sink_mutex_);
  if (sink_writer_) {
    sink_writer_->Finalize();
    SafeRelease(&sink_writer_);
  }
}

bool ScreenRecorder::InitAudioClients() {
  CleanupAudioClients();

  HRESULT hr = CoCreateInstance(
      __uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
      IID_PPV_ARGS(&mm_device_enumerator_));
  if (FAILED(hr)) return false;

  bool want_internal = (config_.audio_source == "Internal" || config_.audio_source == "Internal + Mic");
  bool want_mic = (config_.audio_source == "Microphone" || config_.audio_source == "Internal + Mic");

  // 1. Setup Loopback (Internal System Audio)
  if (want_internal) {
    IMMDevice* render_device = nullptr;
    if (SUCCEEDED(mm_device_enumerator_->GetDefaultAudioEndpoint(eRender, eConsole, &render_device))) {
      if (SUCCEEDED(render_device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr, (void**)&loopback_audio_client_))) {
        if (SUCCEEDED(loopback_audio_client_->GetMixFormat(&loopback_wave_format_))) {
          REFERENCE_TIME hns_buffer = 10000000; // 1 second buffer
          if (SUCCEEDED(loopback_audio_client_->Initialize(
                  AUDCLNT_SHAREMODE_SHARED, AUDCLNT_STREAMFLAGS_LOOPBACK,
                  hns_buffer, 0, loopback_wave_format_, nullptr))) {
            loopback_audio_client_->GetService(IID_PPV_ARGS(&loopback_capture_client_));
            loopback_audio_client_->Start();
          }
        }
      }
      SafeRelease(&render_device);
    }
  }

  // 2. Setup Microphone Capture
  if (want_mic) {
    IMMDevice* capture_device = nullptr;
    if (SUCCEEDED(mm_device_enumerator_->GetDefaultAudioEndpoint(eCapture, eConsole, &capture_device))) {
      if (SUCCEEDED(capture_device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr, (void**)&mic_audio_client_))) {
        if (SUCCEEDED(mic_audio_client_->GetMixFormat(&mic_wave_format_))) {
          REFERENCE_TIME hns_buffer = 10000000;
          if (SUCCEEDED(mic_audio_client_->Initialize(
                  AUDCLNT_SHAREMODE_SHARED, 0,
                  hns_buffer, 0, mic_wave_format_, nullptr))) {
            mic_audio_client_->GetService(IID_PPV_ARGS(&mic_capture_client_));
            mic_audio_client_->Start();
          }
        }
      }
      SafeRelease(&capture_device);
    }
  }

  return (loopback_capture_client_ != nullptr || mic_capture_client_ != nullptr);
}

void ScreenRecorder::CleanupAudioClients() {
  if (loopback_audio_client_) {
    loopback_audio_client_->Stop();
    SafeRelease(&loopback_capture_client_);
    SafeRelease(&loopback_audio_client_);
  }
  if (loopback_wave_format_) {
    CoTaskMemFree(loopback_wave_format_);
    loopback_wave_format_ = nullptr;
  }

  if (mic_audio_client_) {
    mic_audio_client_->Stop();
    SafeRelease(&mic_capture_client_);
    SafeRelease(&mic_audio_client_);
  }
  if (mic_wave_format_) {
    CoTaskMemFree(mic_wave_format_);
    mic_wave_format_ = nullptr;
  }

  SafeRelease(&mm_device_enumerator_);
}

void ScreenRecorder::ScaleBgra(const uint8_t* src, int src_w, int src_h,
                             uint8_t* dst, int dst_w, int dst_h) {
  if (src_w <= 0 || src_h <= 0 || dst_w <= 0 || dst_h <= 0) return;

  // In Media Foundation, MFVideoFormat_RGB32 defaults to bottom-up row ordering
  // (row 0 in buffer = bottom of video frame). Because desktop capture (DXGI / GDI)
  // produces top-down buffers (row 0 = top of screen), we flip scanlines vertically
  // so the encoded video is upright and properly positioned.

  if (src_w == dst_w && src_h == dst_h) {
    const int row_bytes = src_w * 4;
    for (int y = 0; y < src_h; y++) {
      int dst_y = (dst_h - 1) - y;
      memcpy(dst + dst_y * row_bytes, src + y * row_bytes, row_bytes);
    }
    return;
  }

  // Calculate scaling factor preserving aspect ratio (letterboxing / pillarboxing)
  double scale_x = static_cast<double>(dst_w) / static_cast<double>(src_w);
  double scale_y = static_cast<double>(dst_h) / static_cast<double>(src_h);
  double scale = (scale_x < scale_y) ? scale_x : scale_y;

  int scaled_w = static_cast<int>(src_w * scale);
  int scaled_h = static_cast<int>(src_h * scale);
  if (scaled_w > dst_w) scaled_w = dst_w;
  if (scaled_h > dst_h) scaled_h = dst_h;
  if (scaled_w <= 0) scaled_w = 1;
  if (scaled_h <= 0) scaled_h = 1;

  int offset_x = (dst_w - scaled_w) / 2;
  int offset_y = (dst_h - scaled_h) / 2;

  // Fill destination with black background (BGRA: 0, 0, 0, 255)
  uint32_t* dst_u32 = reinterpret_cast<uint32_t*>(dst);
  int total_pixels = dst_w * dst_h;
  for (int i = 0; i < total_pixels; i++) {
    dst_u32[i] = 0xFF000000;
  }

  // Nearest-neighbor resampling into centered letterbox region, inverted vertically for Media Foundation RGB32
  for (int y = 0; y < scaled_h; y++) {
    int src_y = (y * src_h) / scaled_h;
    if (src_y >= src_h) src_y = src_h - 1;
    const uint32_t* src_row = reinterpret_cast<const uint32_t*>(src + src_y * src_w * 4);

    // Map top-down y (0 = top) to bottom-up DIB row in dst
    int dst_y = (dst_h - 1) - (y + offset_y);
    uint32_t* dst_row = dst_u32 + dst_y * dst_w + offset_x;

    for (int x = 0; x < scaled_w; x++) {
      int src_x = (x * src_w) / scaled_w;
      if (src_x >= src_w) src_x = src_w - 1;
      dst_row[x] = src_row[src_x];
    }
  }
}

bool ScreenRecorder::CaptureDXGIFrame(std::vector<uint8_t>& bgra_buffer, int& frame_w, int& frame_h) {
  if (!dxgi_duplication_ || !d3d_context_ || !staging_texture_) {
    return false;
  }

  DXGI_OUTDUPL_FRAME_INFO frame_info;
  IDXGIResource* desktop_resource = nullptr;
  HRESULT hr = dxgi_duplication_->AcquireNextFrame(16, &frame_info, &desktop_resource);

  if (hr == DXGI_ERROR_WAIT_TIMEOUT) {
    // Screen did not change; keep previous buffer
    frame_w = dup_width_;
    frame_h = dup_height_;
    return true;
  }

  if (FAILED(hr)) {
    // Access lost (e.g. UAC prompt, resolution switch), need re-init
    CleanupDXGIDuplication();
    InitDXGIDuplication(0);
    return false;
  }

  ID3D11Texture2D* desktop_texture = nullptr;
  hr = desktop_resource->QueryInterface(__uuidof(ID3D11Texture2D), (void**)&desktop_texture);
  SafeRelease(&desktop_resource);

  if (SUCCEEDED(hr)) {
    d3d_context_->CopyResource(staging_texture_, desktop_texture);
    SafeRelease(&desktop_texture);

    D3D11_MAPPED_SUBRESOURCE mapped;
    hr = d3d_context_->Map(staging_texture_, 0, D3D11_MAP_READ, 0, &mapped);
    if (SUCCEEDED(hr)) {
      frame_w = dup_width_;
      frame_h = dup_height_;
      bgra_buffer.resize(frame_w * frame_h * 4);

      const uint8_t* src_bytes = reinterpret_cast<const uint8_t*>(mapped.pData);
      uint8_t* dst_bytes = bgra_buffer.data();

      for (int y = 0; y < frame_h; y++) {
        memcpy(dst_bytes + y * frame_w * 4, src_bytes + y * mapped.RowPitch, frame_w * 4);
      }

      d3d_context_->Unmap(staging_texture_, 0);

      // Draw Cursor
      CURSORINFO ci = {sizeof(CURSORINFO)};
      if (GetCursorInfo(&ci) && ci.flags == CURSOR_SHOWING) {
        ICONINFO ii;
        if (GetIconInfo(ci.hCursor, &ii)) {
          int cx = ci.ptScreenPos.x - ii.xHotspot;
          int cy = ci.ptScreenPos.y - ii.yHotspot;
          if (cx >= 0 && cx < frame_w - 32 && cy >= 0 && cy < frame_h - 32) {
            HDC screen_dc = GetDC(nullptr);
            HDC mem_dc = CreateCompatibleDC(screen_dc);
            HBITMAP dib = CreateBitmap(frame_w, frame_h, 1, 32, bgra_buffer.data());
            SelectObject(mem_dc, dib);
            DrawIconEx(mem_dc, cx, cy, ci.hCursor, 0, 0, 0, nullptr, DI_NORMAL);
            GetBitmapBits(dib, static_cast<LONG>(bgra_buffer.size()), bgra_buffer.data());
            DeleteObject(dib);
            DeleteDC(mem_dc);
            ReleaseDC(nullptr, screen_dc);
          }
          if (ii.hbmColor) DeleteObject(ii.hbmColor);
          if (ii.hbmMask) DeleteObject(ii.hbmMask);
        }
      }

      dxgi_duplication_->ReleaseFrame();
      return true;
    }
  }

  dxgi_duplication_->ReleaseFrame();
  return false;
}

bool ScreenRecorder::CaptureGDIFrame(HWND hwnd, std::vector<uint8_t>& bgra_buffer, int& frame_w, int& frame_h) {
  RECT r;
  HDC src_dc = nullptr;

  if (hwnd && IsWindow(hwnd)) {
    GetClientRect(hwnd, &r);
    src_dc = GetDC(hwnd);
  } else {
    // Entire primary desktop
    r.left = 0;
    r.top = 0;
    r.right = GetSystemMetrics(SM_CXSCREEN);
    r.bottom = GetSystemMetrics(SM_CYSCREEN);
    src_dc = GetDC(nullptr);
  }

  int w = r.right - r.left;
  int h = r.bottom - r.top;
  if (w <= 0 || h <= 0) {
    if (src_dc) ReleaseDC(hwnd, src_dc);
    return false;
  }

  frame_w = w;
  frame_h = h;
  bgra_buffer.resize(w * h * 4);

  HDC mem_dc = CreateCompatibleDC(src_dc);

  BITMAPINFO bmi = {};
  bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bmi.bmiHeader.biWidth = w;
  bmi.bmiHeader.biHeight = -h;  // Top-down
  bmi.bmiHeader.biPlanes = 1;
  bmi.bmiHeader.biBitCount = 32;
  bmi.bmiHeader.biCompression = BI_RGB;

  void* bits = nullptr;
  HBITMAP dib = CreateDIBSection(mem_dc, &bmi, DIB_RGB_COLORS, &bits, nullptr, 0);
  HBITMAP old_bm = reinterpret_cast<HBITMAP>(SelectObject(mem_dc, dib));

  if (hwnd && IsWindow(hwnd)) {
    if (!PrintWindow(hwnd, mem_dc, PW_RENDERFULLCONTENT)) {
      BitBlt(mem_dc, 0, 0, w, h, src_dc, 0, 0, SRCCOPY);
    }
  } else {
    BitBlt(mem_dc, 0, 0, w, h, src_dc, 0, 0, SRCCOPY);
  }

  // Draw Cursor
  CURSORINFO ci = {sizeof(CURSORINFO)};
  if (GetCursorInfo(&ci) && ci.flags == CURSOR_SHOWING) {
    POINT pt = ci.ptScreenPos;
    if (hwnd) ScreenToClient(hwnd, &pt);
    DrawIconEx(mem_dc, pt.x, pt.y, ci.hCursor, 0, 0, 0, nullptr, DI_NORMAL);
  }

  if (bits) {
    memcpy(bgra_buffer.data(), bits, w * h * 4);
  }

  SelectObject(mem_dc, old_bm);
  DeleteObject(dib);
  DeleteDC(mem_dc);
  ReleaseDC(hwnd, src_dc);

  return true;
}

void ScreenRecorder::VideoCaptureLoop() {
  std::vector<uint8_t> raw_frame;
  std::vector<uint8_t> scaled_frame(target_width_ * target_height_ * 4);

  bool is_window = (config_.source_id.rfind("window:", 0) == 0);
  HWND target_hwnd = nullptr;
  if (is_window) {
    uintptr_t ptr = std::strtoull(config_.source_id.substr(7).c_str(), nullptr, 10);
    target_hwnd = reinterpret_cast<HWND>(ptr);
  }

  int raw_w = 0;
  int raw_h = 0;
  LONGLONG sample_time = 0;

  while (!stop_requested_) {
    auto loop_start = std::chrono::steady_clock::now();

    if (is_paused_) {
      std::this_thread::sleep_for(std::chrono::milliseconds(30));
      continue;
    }

    bool captured = false;
    if (is_window && target_hwnd) {
      if (!IsWindow(target_hwnd)) {
        // Window was closed during recording
        break;
      }
      captured = CaptureGDIFrame(target_hwnd, raw_frame, raw_w, raw_h);
    } else {
      // Monitor capture
      if (dxgi_duplication_) {
        captured = CaptureDXGIFrame(raw_frame, raw_w, raw_h);
      }
      if (!captured) {
        // Fallback to GDI
        captured = CaptureGDIFrame(nullptr, raw_frame, raw_w, raw_h);
      }
    }

    if (captured && !raw_frame.empty()) {
      if (is_video_enabled_.load()) {
        ScaleBgra(raw_frame.data(), raw_w, raw_h,
                  scaled_frame.data(), target_width_, target_height_);
      } else {
        // Black frame when video disabled
        memset(scaled_frame.data(), 0, scaled_frame.size());
      }

      // Write Video Sample
      std::lock_guard<std::mutex> lock(sink_mutex_);
      if (sink_writer_) {
        IMFMediaBuffer* buffer = nullptr;
        if (SUCCEEDED(MFCreateMemoryBuffer(static_cast<DWORD>(scaled_frame.size()), &buffer))) {
          BYTE* data = nullptr;
          if (SUCCEEDED(buffer->Lock(&data, nullptr, nullptr))) {
            memcpy(data, scaled_frame.data(), scaled_frame.size());
            buffer->Unlock();
            buffer->SetCurrentLength(static_cast<DWORD>(scaled_frame.size()));

            IMFSample* sample = nullptr;
            if (SUCCEEDED(MFCreateSample(&sample))) {
              sample->AddBuffer(buffer);
              sample->SetSampleTime(sample_time);
              sample->SetSampleDuration(frame_duration_hns_);
              sink_writer_->WriteSample(video_stream_index_, sample);
              SafeRelease(&sample);
            }
          }
          SafeRelease(&buffer);
        }
      }

      sample_time += frame_duration_hns_;
    }

    // Pace loop to target FPS
    auto loop_end = std::chrono::steady_clock::now();
    auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(loop_end - loop_start);
    int target_delay_ms = static_cast<int>(frame_duration_hns_ / 10000);
    if (elapsed.count() < target_delay_ms) {
      std::this_thread::sleep_for(std::chrono::milliseconds(target_delay_ms - elapsed.count()));
    }
  }
}

void ScreenRecorder::AudioCaptureLoop() {
  LONGLONG audio_time = 0;
  const int kTargetSampleRate = 48000;
  const int kChannels = 2;
  const int kChunkFrames = 960; // 20ms chunk
  const DWORD kChunkBytes = kChunkFrames * kChannels * sizeof(int16_t);

  std::vector<int16_t> pcm_chunk(kChunkFrames * kChannels, static_cast<int16_t>(0));

  while (!stop_requested_) {
    if (is_paused_) {
      std::this_thread::sleep_for(std::chrono::milliseconds(20));
      continue;
    }

    memset(pcm_chunk.data(), 0, pcm_chunk.size() * sizeof(int16_t));

    // 1. Capture Loopback Audio (System)
    if (loopback_capture_client_) {
      UINT32 packet_length = 0;
      while (SUCCEEDED(loopback_capture_client_->GetNextPacketSize(&packet_length)) && packet_length > 0) {
        BYTE* data = nullptr;
        UINT32 num_frames = 0;
        DWORD flags = 0;
        if (SUCCEEDED(loopback_capture_client_->GetBuffer(&data, &num_frames, &flags, nullptr, nullptr))) {
          if (!(flags & AUDCLNT_BUFFERFLAGS_SILENT) && loopback_wave_format_) {
            const float* float_data = reinterpret_cast<const float*>(data);
            int in_channels = loopback_wave_format_->nChannels;
            int frames_to_mix = std::min<int>(num_frames, kChunkFrames);

            for (int i = 0; i < frames_to_mix; i++) {
              float l = float_data[i * in_channels];
              float r = (in_channels > 1) ? float_data[i * in_channels + 1] : l;
              pcm_chunk[i * 2] = static_cast<int16_t>(std::clamp(l * 32767.0f, -32768.0f, 32767.0f));
              pcm_chunk[i * 2 + 1] = static_cast<int16_t>(std::clamp(r * 32767.0f, -32768.0f, 32767.0f));
            }
          }
          loopback_capture_client_->ReleaseBuffer(num_frames);
        }
      }
    }

    // 2. Capture Microphone Audio
    if (mic_capture_client_ && !is_mic_muted_.load()) {
      UINT32 packet_length = 0;
      while (SUCCEEDED(mic_capture_client_->GetNextPacketSize(&packet_length)) && packet_length > 0) {
        BYTE* data = nullptr;
        UINT32 num_frames = 0;
        DWORD flags = 0;
        if (SUCCEEDED(mic_capture_client_->GetBuffer(&data, &num_frames, &flags, nullptr, nullptr))) {
          if (!(flags & AUDCLNT_BUFFERFLAGS_SILENT) && mic_wave_format_) {
            const float* float_data = reinterpret_cast<const float*>(data);
            int in_channels = mic_wave_format_->nChannels;
            int frames_to_mix = std::min<int>(num_frames, kChunkFrames);

            for (int i = 0; i < frames_to_mix; i++) {
              float m_l = float_data[i * in_channels];
              float m_r = (in_channels > 1) ? float_data[i * in_channels + 1] : m_l;
              int cur_l = pcm_chunk[i * 2];
              int cur_r = pcm_chunk[i * 2 + 1];
              int mixed_l = cur_l + static_cast<int>(m_l * 32767.0f);
              int mixed_r = cur_r + static_cast<int>(m_r * 32767.0f);
              pcm_chunk[i * 2] = static_cast<int16_t>(std::clamp(mixed_l, -32768, 32767));
              pcm_chunk[i * 2 + 1] = static_cast<int16_t>(std::clamp(mixed_r, -32768, 32767));
            }
          }
          mic_capture_client_->ReleaseBuffer(num_frames);
        }
      }
    }

    // Write Audio Sample to SinkWriter
    {
      std::lock_guard<std::mutex> lock(sink_mutex_);
      if (sink_writer_) {
        IMFMediaBuffer* buffer = nullptr;
        if (SUCCEEDED(MFCreateMemoryBuffer(kChunkBytes, &buffer))) {
          BYTE* data = nullptr;
          if (SUCCEEDED(buffer->Lock(&data, nullptr, nullptr))) {
            memcpy(data, pcm_chunk.data(), kChunkBytes);
            buffer->Unlock();
            buffer->SetCurrentLength(kChunkBytes);

            IMFSample* sample = nullptr;
            if (SUCCEEDED(MFCreateSample(&sample))) {
              sample->AddBuffer(buffer);
              sample->SetSampleTime(audio_time);
              LONGLONG chunk_duration = (static_cast<LONGLONG>(kChunkFrames) * 10000000) / kTargetSampleRate;
              sample->SetSampleDuration(chunk_duration);
              sink_writer_->WriteSample(audio_stream_index_, sample);
              SafeRelease(&sample);
            }
          }
          SafeRelease(&buffer);
        }
      }
    }

    audio_time += (static_cast<LONGLONG>(kChunkFrames) * 10000000) / kTargetSampleRate;
    std::this_thread::sleep_for(std::chrono::milliseconds(20));
  }
}

VideoFileMetadata ScreenRecorder::GetVideoMetadata(const std::string& file_path) {
  VideoFileMetadata meta;
  std::wstring wide_path = Utf8ToWide(file_path);

  IMFSourceReader* reader = nullptr;
  HRESULT hr = MFCreateSourceReaderFromURL(wide_path.c_str(), nullptr, &reader);
  if (FAILED(hr)) return meta;

  // Duration
  PROPVARIANT var;
  PropVariantInit(&var);
  if (SUCCEEDED(reader->GetPresentationAttribute(static_cast<DWORD>(MF_SOURCE_READER_MEDIASOURCE), MF_PD_DURATION, &var))) {
    if (var.vt == VT_UI8) {
      meta.duration_ms = var.uhVal.QuadPart / 10000;
    }
    PropVariantClear(&var);
  }

  // Video Stream Format
  IMFMediaType* media_type = nullptr;
  if (SUCCEEDED(reader->GetCurrentMediaType(static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM), &media_type))) {
    UINT32 w = 0, h = 0;
    MFGetAttributeSize(media_type, MF_MT_FRAME_SIZE, &w, &h);
    meta.width = static_cast<int>(w);
    meta.height = static_cast<int>(h);

    UINT32 num = 0, den = 0;
    if (SUCCEEDED(MFGetAttributeRatio(media_type, MF_MT_FRAME_RATE, &num, &den)) && den > 0) {
      meta.fps = static_cast<double>(num) / static_cast<double>(den);
    }

    UINT32 avg_bitrate = 0;
    if (SUCCEEDED(media_type->GetUINT32(MF_MT_AVG_BITRATE, &avg_bitrate))) {
      meta.bitrate_bps = static_cast<int>(avg_bitrate);
    }

    SafeRelease(&media_type);
  }

  SafeRelease(&reader);
  return meta;
}

void ScreenRecorder::GetStorageInfo(int64_t& available_bytes, int64_t& total_bytes) {
  ULARGE_INTEGER free_bytes_avail, total_num_bytes, total_free_bytes;
  if (GetDiskFreeSpaceExW(nullptr, &free_bytes_avail, &total_num_bytes, &total_free_bytes)) {
    available_bytes = static_cast<int64_t>(free_bytes_avail.QuadPart);
    total_bytes = static_cast<int64_t>(total_num_bytes.QuadPart);
  } else {
    available_bytes = 0;
    total_bytes = 0;
  }
}
