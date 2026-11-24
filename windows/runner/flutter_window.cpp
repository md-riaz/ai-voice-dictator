#include "flutter_window.h"

#include <optional>
#include <cmath>
#include <cassert>
#include <algorithm>
#include <gdiplus.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"

namespace {
std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> keys;
HHOOK hook = nullptr;
HWND key_window = nullptr;
HWND hud_window = nullptr;
std::wstring hud_text = L"Please wait before speaking...";
COLORREF hud_color = RGB(79, 70, 229);
bool hud_success = false;
bool hud_writing = false;
bool hud_preparing = false;
bool hud_listening = false;
double hud_level = 0;
bool hud_timer_running = false;
ULONG_PTR gdiplus_token = 0;
constexpr unsigned kCtrl = 1, kWin = 2, kAlt = 4, kShift = 8, kSpace = 16;
unsigned hold_chord = kCtrl | kWin;
unsigned translation_chord = kCtrl | kWin | kAlt;
unsigned hands_free_chord = kCtrl | kWin | kSpace;
unsigned hands_free_key = VK_SPACE;
unsigned previous_keys = 0;
bool hold_started = false, translating = false, chord_used = false, recording = false;
bool swallowed_key = false;
constexpr UINT_PTR kHoldTimer = 102;
constexpr UINT_PTR kHudTimer = 103;

constexpr bool MatchesChord(unsigned pressed, unsigned chord) { return pressed == chord; }
static_assert(MatchesChord(kCtrl | kWin, kCtrl | kWin));
static_assert(!MatchesChord(kCtrl, kCtrl | kWin));
static_assert(!MatchesChord(kSpace, kCtrl | kWin | kSpace));
static_assert(!MatchesChord(kCtrl | kWin | kAlt, kCtrl | kWin));

unsigned PhysicalKeys() {
  unsigned pressed = 0;
  if (GetAsyncKeyState(VK_CONTROL) & 0x8000) pressed |= kCtrl;
  if ((GetAsyncKeyState(VK_LWIN) | GetAsyncKeyState(VK_RWIN)) & 0x8000) pressed |= kWin;
  if (GetAsyncKeyState(VK_MENU) & 0x8000) pressed |= kAlt;
  if (GetAsyncKeyState(VK_SHIFT) & 0x8000) pressed |= kShift;
  if (GetAsyncKeyState(hands_free_key) & 0x8000) pressed |= kSpace;
  return pressed;
}

unsigned ModifierForKey(DWORD key) {
  if (key == VK_CONTROL || key == VK_LCONTROL || key == VK_RCONTROL) return kCtrl;
  if (key == VK_LWIN || key == VK_RWIN) return kWin;
  if (key == VK_MENU || key == VK_LMENU || key == VK_RMENU) return kAlt;
  if (key == VK_SHIFT || key == VK_LSHIFT || key == VK_RSHIFT) return kShift;
  if (key == hands_free_key) return kSpace;
  return 0;
}

unsigned OtherSideKey(DWORD key) {
  switch (key) {
    case VK_LCONTROL: return VK_RCONTROL;
    case VK_RCONTROL: return VK_LCONTROL;
    case VK_LWIN: return VK_RWIN;
    case VK_RWIN: return VK_LWIN;
    case VK_LMENU: return VK_RMENU;
    case VK_RMENU: return VK_LMENU;
    case VK_LSHIFT: return VK_RSHIFT;
    case VK_RSHIFT: return VK_LSHIFT;
    default: return 0;
  }
}

bool ParseChord(const std::string& value, unsigned* result) {
  unsigned pressed = 0;
  size_t start = 0;
  while (start < value.size()) {
    const auto end = value.find('+', start);
    const auto part = value.substr(start, end == std::string::npos ? end : end - start);
    unsigned bit = part == "Ctrl" ? kCtrl : part == "Win" ? kWin :
                   part == "Alt" ? kAlt : part == "Shift" ? kShift :
                   part == "Space" ? kSpace : 0;
    if (!bit || (pressed & bit)) return false;
    pressed |= bit;
    if (end == std::string::npos) break;
    start = end + 1;
    if (start == value.size()) return false;
  }
  *result = pressed;
  return pressed != 0;
}

unsigned ParseHandsFreeKey(const std::string& value) {
  if (value == "Space") return VK_SPACE;
  if (value.size() == 1 && ((value[0] >= 'A' && value[0] <= 'Z') ||
                            (value[0] >= '0' && value[0] <= '9'))) return value[0];
  if (value.size() >= 2 && value[0] == 'F') {
    unsigned number = 0;
    for (size_t i = 1; i < value.size(); ++i) {
      if (value[i] < '0' || value[i] > '9') return 0;
      number = number * 10 + value[i] - '0';
      if (number > 12) return 0;
    }
    if (number >= 1 && value == "F" + std::to_string(number)) return VK_F1 + number - 1;
  }
  return 0;
}

constexpr bool HasVisibleTitleBar(const RECT& window, const RECT& work) {
  const LONG left = window.left > work.left ? window.left : work.left;
  const LONG right = window.right < work.right ? window.right : work.right;
  const LONG top = window.top > work.top ? window.top : work.top;
  const LONG title_bottom = window.top + 32;
  const LONG bottom = title_bottom < work.bottom ? title_bottom : work.bottom;
  return right - left >= 64 && bottom - top >= 24;
}

constexpr bool HasUsableWindowSize(const RECT& window) {
  return window.right - window.left >= 600 && window.bottom - window.top >= 400;
}

static_assert(HasVisibleTitleBar({100, 100, 900, 700}, {0, 0, 1920, 1080}));
static_assert(!HasVisibleTitleBar({2000, 100, 2800, 700}, {0, 0, 1920, 1080}));
static_assert(!HasVisibleTitleBar({100, -100, 900, 500}, {0, 0, 1920, 1080}));
static_assert(!HasUsableWindowSize({0, 0, 180, 45}));
static_assert(HasUsableWindowSize({0, 0, 900, 700}));

void EnsureWindowVisible() {
  RECT bounds;
  if (!GetWindowRect(key_window, &bounds)) return;
  HMONITOR monitor = MonitorFromWindow(key_window, MONITOR_DEFAULTTONEAREST);
  MONITORINFO info = {sizeof(info)};
  if (!monitor || !GetMonitorInfoW(monitor, &info)) return;
  const LONG work_width = info.rcWork.right - info.rcWork.left;
  const LONG work_height = info.rcWork.bottom - info.rcWork.top;
  if (HasVisibleTitleBar(bounds, info.rcWork) &&
      (HasUsableWindowSize(bounds) || (work_width < 600 || work_height < 400))) return;
  const LONG width = (std::min)((std::max)(bounds.right - bounds.left, 600L), work_width);
  const LONG height = (std::min)((std::max)(bounds.bottom - bounds.top, 400L), work_height);
  SetWindowPos(key_window, nullptr, info.rcWork.left + (work_width - width) / 2,
               info.rcWork.top + (work_height - height) / 2, width, height,
               SWP_NOZORDER | SWP_NOACTIVATE);
}

std::wstring Wide(const std::string& text) {
  if (text.empty()) return {};
  int size = MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0);
  std::wstring out(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), out.data(), size);
  return out;
}

LRESULT CALLBACK HudProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == WM_ERASEBKGND) return 1;
  if (message == WM_TIMER && wparam == kHudTimer) {
    InvalidateRect(hwnd, nullptr, FALSE);
    return 0;
  }
  if (message == WM_PAINT) {
    PAINTSTRUCT paint;
    HDC window_dc = BeginPaint(hwnd, &paint);
    RECT bounds; GetClientRect(hwnd, &bounds);
    HDC buffer_dc = CreateCompatibleDC(window_dc);
    HBITMAP buffer = buffer_dc ? CreateCompatibleBitmap(window_dc, bounds.right, bounds.bottom) : nullptr;
    HGDIOBJ old_bitmap = buffer ? SelectObject(buffer_dc, buffer) : nullptr;
    HDC dc = buffer ? buffer_dc : window_dc;
    HBRUSH bg = CreateSolidBrush(RGB(248, 250, 252));
    FillRect(dc, &bounds, bg); DeleteObject(bg);
    const int cy = bounds.bottom / 2;
    HPEN border = CreatePen(PS_SOLID, 1, RGB(199, 210, 254));
    HGDIOBJ oldPen = SelectObject(dc, border);
    HGDIOBJ oldBrush = SelectObject(dc, GetStockObject(NULL_BRUSH));
    RoundRect(dc, 0, 0, bounds.right - 1, bounds.bottom - 1, 32, 32);
    SelectObject(dc, oldBrush); SelectObject(dc, oldPen); DeleteObject(border);
    HPEN iconPen = CreatePen(PS_SOLID, 3, hud_color);
    oldPen = SelectObject(dc, iconPen);
    if (hud_preparing || hud_writing) {
      const double angle = (GetTickCount64() % 960) * 6.283185307179586 / 960;
      if (gdiplus_token) {
        Gdiplus::Graphics graphics(dc);
        graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
        Gdiplus::Pen pen(Gdiplus::Color(GetRValue(hud_color), GetGValue(hud_color), GetBValue(hud_color)), 3.0f);
        pen.SetStartCap(Gdiplus::LineCapRound);
        pen.SetEndCap(Gdiplus::LineCapRound);
        graphics.DrawArc(&pen, 20.0f, static_cast<float>(cy - 10), 20.0f, 20.0f,
                         static_cast<float>((GetTickCount64() % 960) * 360.0 / 960), 270.0f);
      } else {
        Arc(dc, 20, cy - 10, 40, cy + 10,
            30 + static_cast<int>(10 * std::cos(angle)),
            cy + static_cast<int>(10 * std::sin(angle)),
            30 + static_cast<int>(10 * std::cos(angle + 1.5)),
            cy + static_cast<int>(10 * std::sin(angle + 1.5)));
      }
    } else if (hud_listening) {
      const int heights[] = {3, 6, 10, 6, 3};
      for (int i = 0; i < 5; ++i) {
        const int height = 1 + static_cast<int>(heights[i] * hud_level);
        MoveToEx(dc, 20 + i * 5, cy - height, nullptr);
        LineTo(dc, 20 + i * 5, cy + height);
      }
    } else if (hud_success) {
      MoveToEx(dc, 20, cy, nullptr); LineTo(dc, 26, cy + 6); LineTo(dc, 40, cy - 8);
    } else {
      MoveToEx(dc, 30, cy - 8, nullptr); LineTo(dc, 30, cy + 4);
      Ellipse(dc, 28, cy + 7, 32, cy + 11);
    }
    SelectObject(dc, oldPen); DeleteObject(iconPen);
    SetBkMode(dc, TRANSPARENT); SetTextColor(dc, RGB(15, 23, 42));
    HFONT font = CreateFontW(-16, 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
                            DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                            CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Segoe UI");
    HGDIOBJ oldFont = SelectObject(dc, font);
    RECT text = {55, 8, bounds.right - 16, bounds.bottom - 8};
    DrawTextW(dc, hud_text.c_str(), -1, &text, DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS | DT_NOPREFIX);
    SelectObject(dc, oldFont); DeleteObject(font);
    if (buffer) {
      BitBlt(window_dc, 0, 0, bounds.right, bounds.bottom, buffer_dc, 0, 0, SRCCOPY);
      SelectObject(buffer_dc, old_bitmap);
      DeleteObject(buffer);
    }
    if (buffer_dc) DeleteDC(buffer_dc);
    EndPaint(hwnd, &paint); return 0;
  }
  if (message == WM_MOUSEACTIVATE) return MA_NOACTIVATE;
  return DefWindowProc(hwnd, message, wparam, lparam);
}

bool CreateHud() {
  if (!gdiplus_token) {
    Gdiplus::GdiplusStartupInput input;
    Gdiplus::GdiplusStartup(&gdiplus_token, &input, nullptr);
  }
  WNDCLASSW wc = {}; wc.lpfnWndProc = HudProc;
  wc.hInstance = GetModuleHandle(nullptr); wc.lpszClassName = L"AiDictatorHud";
  if (!RegisterClassW(&wc) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) return false;
  hud_window = CreateWindowExW(WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_LAYERED | WS_EX_TRANSPARENT,
      wc.lpszClassName, L"Dictation status", WS_POPUP, 0, 0, 340, 64, nullptr, nullptr, wc.hInstance, nullptr);
  if (!hud_window) return false;
  SetLayeredWindowAttributes(hud_window, 0, 240, LWA_ALPHA);
  return true;
}

void ShowHud() {
  if (!hud_window && !CreateHud()) return;
  RECT work;
  MONITORINFO monitor_info = {sizeof(monitor_info)};
  HMONITOR monitor = MonitorFromWindow(GetForegroundWindow(), MONITOR_DEFAULTTOPRIMARY);
  if (monitor && GetMonitorInfoW(monitor, &monitor_info)) {
    work = monitor_info.rcWork;
  } else {
    SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0);
  }
  HDC dc = GetDC(hud_window);
  HFONT font = CreateFontW(-16, 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
                           DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                           CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Segoe UI");
  HGDIOBJ oldFont = SelectObject(dc, font);
  RECT measured = {0, 0, 0, 0};
  DrawTextW(dc, hud_text.c_str(), -1, &measured, DT_SINGLELINE | DT_CALCRECT | DT_NOPREFIX);
  SelectObject(dc, oldFont); DeleteObject(font); ReleaseDC(hud_window, dc);
  const int width = (std::min)((std::min)((std::max)(340, static_cast<int>(measured.right + 71)), 560),
                               static_cast<int>(work.right - work.left));
  const int height = 64;
  SetWindowRgn(hud_window, CreateRoundRectRgn(0, 0, width + 1, height + 1, 32, 32), TRUE);
  SetWindowPos(hud_window, HWND_TOPMOST, work.left + (work.right - work.left - width) / 2,
               work.bottom - height - 32, width, height, SWP_NOACTIVATE | SWP_SHOWWINDOW);
  InvalidateRect(hud_window, nullptr, FALSE);
}

void UpdateHudAnimation() {
  if (!hud_window) return;
  const bool animate = (hud_writing || hud_preparing) && IsWindowVisible(hud_window);
  if (animate && !hud_timer_running) {
    hud_timer_running = SetTimer(hud_window, kHudTimer, 16, nullptr) != 0;
  } else if (!animate && hud_timer_running) {
    KillTimer(hud_window, kHudTimer);
    hud_timer_running = false;
  }
}

void Emit(const char* event) {
  if (keys) keys->InvokeMethod(event, nullptr);
}

LRESULT CALLBACK KeyboardHook(int code, WPARAM message, LPARAM data) {
  if (code < 0) return CallNextHookEx(hook, code, message, data);
  auto* event = reinterpret_cast<KBDLLHOOKSTRUCT*>(data);
  if (event->flags & LLKHF_INJECTED) return CallNextHookEx(hook, code, message, data);
  const bool down = message == WM_KEYDOWN || message == WM_SYSKEYDOWN;
  const bool up = message == WM_KEYUP || message == WM_SYSKEYUP;
  if (!down && !up) return CallNextHookEx(hook, code, message, data);
  const auto key = event->vkCode;
  if (key == VK_ESCAPE && down && (recording || (hud_window && IsWindowVisible(hud_window)))) {
    KillTimer(key_window, kHoldTimer);
    hold_started = false;
    chord_used = true;
    Emit("cancel");
    return 1;
  }
  const unsigned bit = ModifierForKey(key);
  if (!bit) {
    if (down && !hold_started && (PhysicalKeys() & hold_chord) == hold_chord) {
      KillTimer(key_window, kHoldTimer);
      chord_used = true;
    }
    return CallNextHookEx(hook, code, message, data);
  }
  unsigned current = PhysicalKeys();
  if (down) {
    current |= bit;
  } else {
    const unsigned other = OtherSideKey(key);
    if (!other || !(GetAsyncKeyState(other) & 0x8000)) current &= ~bit;
  }
  const bool changed = current != previous_keys;
  previous_keys = current;

  if (up && key == hands_free_key && swallowed_key) {
    swallowed_key = false;
    return 1;
  }
  if (down && key == hands_free_key && swallowed_key) return 1;
  if (hold_started && ((current & (translating ? translation_chord : hold_chord)) !=
                       (translating ? translation_chord : hold_chord))) {
    hold_started = false;
    translating = false;
    chord_used = true;
    Emit("holdStop");
  }
  if (!MatchesChord(current, hold_chord)) KillTimer(key_window, kHoldTimer);
  if (down && changed && !chord_used && MatchesChord(current, hands_free_chord)) {
    KillTimer(key_window, kHoldTimer);
    Emit("handsFree");
    hold_started = false;
    translating = false;
    chord_used = true;
    if (key == hands_free_key) { swallowed_key = true; return 1; }
  } else if (down && changed && !chord_used && MatchesChord(current, translation_chord)) {
    KillTimer(key_window, kHoldTimer);
    Emit(hold_started ? "switchTranslation" : "translationStart");
    hold_started = true;
    translating = true;
  } else if (down && changed && !hold_started && !chord_used && MatchesChord(current, hold_chord)) {
    SetTimer(key_window, kHoldTimer, 180, nullptr);
  }
  if ((current & hold_chord) == 0) chord_used = false;
  return CallNextHookEx(hook, code, message, data);
}
}

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {
  assert(ParseHandsFreeKey("Space") == VK_SPACE);
  assert(ParseHandsFreeKey("A") == 'A');
  assert(ParseHandsFreeKey("F12") == VK_F12);
  assert(ParseHandsFreeKey("F13") == 0);
  assert(ParseHandsFreeKey("F01") == 0);
}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  key_window = GetHandle();
  keys = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "ai_voice_dictator/keys",
      &flutter::StandardMethodCodec::GetInstance());
  keys->SetMethodCallHandler([](const auto& call, auto result) {
    if (call.method_name() == "setRecording") {
      const auto* value = std::get_if<bool>(call.arguments());
      recording = value && *value;
      result->Success();
    } else if (call.method_name() == "available") {
      result->Success(flutter::EncodableValue(hook != nullptr));
    } else if (call.method_name() == "configureShortcuts") {
      const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
      auto read = [args](const char* name, unsigned* chord) {
        if (!args) return false;
        auto entry = args->find(flutter::EncodableValue(name));
        if (entry == args->end()) return false;
        auto value = std::get_if<std::string>(&entry->second);
        return value && ParseChord(*value, chord);
      };
      unsigned hold = 0, translation = 0, hands_free = 0, new_key = 0;
      if (args) {
        auto entry = args->find(flutter::EncodableValue("handsFree"));
        if (entry != args->end()) {
          if (const auto* value = std::get_if<std::string>(&entry->second)) {
            const auto split = value->rfind('+');
            if (split != std::string::npos && ParseChord(value->substr(0, split), &hands_free)) {
              new_key = ParseHandsFreeKey(value->substr(split + 1));
            }
          }
        }
      }
      if (recording || swallowed_key || !read("hold", &hold) || !read("translation", &translation) ||
          !new_key || (hold & kSpace) ||
          (hold & (hold - 1)) == 0 || translation == hold ||
          (translation & hold) != hold || (translation & kSpace) ||
          hands_free != hold) {
        result->Error("invalid_shortcut", "Shortcuts must use distinct supported combinations.");
      } else {
        KillTimer(key_window, kHoldTimer);
        hold_chord = hold; translation_chord = translation; hands_free_chord = hands_free | kSpace;
        hands_free_key = new_key;
        previous_keys = PhysicalKeys();
        hold_started = false; translating = false; chord_used = previous_keys != 0;
        result->Success(flutter::EncodableValue(true));
      }
    } else if (call.method_name() == "ensureWindowVisible") {
      EnsureWindowVisible(); result->Success();
    } else if (call.method_name() == "showHud") {
      ShowHud(); UpdateHudAnimation(); result->Success();
    } else if (call.method_name() == "hideHud") {
      if (hud_window) { KillTimer(hud_window, kHudTimer); hud_timer_running = false; ShowWindow(hud_window, SW_HIDE); }
      result->Success();
    } else if (call.method_name() == "updateHudLevel") {
      const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
      if (args) {
        const auto level = args->find(flutter::EncodableValue("level"));
        const double* value = level == args->end() ? nullptr : std::get_if<double>(&level->second);
        if (value && std::isfinite(*value) && hud_listening) {
          hud_level = (std::clamp)(*value, 0.0, 1.0);
          if (hud_window) InvalidateRect(hud_window, nullptr, FALSE);
        }
      }
      result->Success();
    } else if (call.method_name() == "updateHud") {
      const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
      if (args) {
        const auto state = args->find(flutter::EncodableValue("state"));
        const auto message = args->find(flutter::EncodableValue("message"));
        const auto seconds = args->find(flutter::EncodableValue("seconds"));
        const std::string* s = state == args->end() ? nullptr : std::get_if<std::string>(&state->second);
        const std::string* m = message == args->end() ? nullptr : std::get_if<std::string>(&message->second);
        const int32_t* n = seconds == args->end() ? nullptr : std::get_if<int32_t>(&seconds->second);
        hud_preparing = s && *s == "preparing";
        hud_listening = s && *s == "listening";
        if (!hud_listening) hud_level = 0;
        hud_success = s && *s == "success";
        hud_writing = s && *s == "writing";
        if (s && *s == "preparing") {
          hud_text = L"Preparing..."; hud_color = RGB(79, 70, 229);
        } else if (s && *s == "listening") {
          hud_text = m && !m->empty() ? Wide(*m) : L"Listening...  " + std::to_wstring(n ? *n / 60 : 0) + L":" + ((n && *n % 60 >= 10) ? L"" : L"0") + std::to_wstring(n ? *n % 60 : 0);
          hud_color = RGB(79, 70, 229);
        } else if (s && *s == "writing") { hud_text = m && !m->empty() ? Wide(*m) : L"Turning speech into text..."; hud_color = RGB(79, 70, 229); }
        else if (s && *s == "success") { hud_text = L"Done"; hud_color = RGB(16, 185, 129); }
        else if (s && *s == "error") { hud_text = m && !m->empty() ? Wide(*m) : L"Error occurred"; hud_color = RGB(245, 158, 11); }
        UpdateHudAnimation();
        if (hud_window && IsWindowVisible(hud_window)) ShowHud();
      }
      result->Success();
    } else {
      result->NotImplemented();
    }
  });
  hook = SetWindowsHookEx(WH_KEYBOARD_LL, KeyboardHook, GetModuleHandle(nullptr), 0);

  // The Dart side shows the window only for settings or the inactive HUD.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  KillTimer(key_window, kHoldTimer);
  if (hook) UnhookWindowsHookEx(hook);
  hook = nullptr;
  if (hud_window) { KillTimer(hud_window, kHudTimer); DestroyWindow(hud_window); }
  hud_window = nullptr;
  if (gdiplus_token) Gdiplus::GdiplusShutdown(gdiplus_token);
  gdiplus_token = 0;
  keys.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_TIMER:
      if (wparam == kHoldTimer) {
        KillTimer(hwnd, kHoldTimer);
        if (MatchesChord(PhysicalKeys(), hold_chord) && !chord_used && !hold_started) {
          hold_started = true;
          translating = false;
          Emit("holdStart");
        }
        return 0;
      }
      break;
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
