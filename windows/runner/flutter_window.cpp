#include "flutter_window.h"

#include <optional>
#include <cmath>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"

namespace {
std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> keys;
HHOOK hook = nullptr;
HWND key_window = nullptr;
HWND hud_window = nullptr;
std::wstring hud_text = L"Please wait before speaking...";
COLORREF hud_color = RGB(255, 104, 104);
bool hud_success = false;
bool hud_writing = false;
constexpr unsigned kCtrl = 1, kWin = 2, kAlt = 4, kShift = 8, kSpace = 16;
unsigned hold_chord = kCtrl | kWin;
unsigned translation_chord = kCtrl | kWin | kAlt;
unsigned hands_free_chord = kCtrl | kWin | kSpace;
unsigned previous_keys = 0;
bool hold_started = false, translating = false, chord_used = false, recording = false;
bool swallowed_space = false;
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
  if (GetAsyncKeyState(VK_SPACE) & 0x8000) pressed |= kSpace;
  return pressed;
}

unsigned ModifierForKey(DWORD key) {
  if (key == VK_CONTROL || key == VK_LCONTROL || key == VK_RCONTROL) return kCtrl;
  if (key == VK_LWIN || key == VK_RWIN) return kWin;
  if (key == VK_MENU || key == VK_LMENU || key == VK_RMENU) return kAlt;
  if (key == VK_SHIFT || key == VK_LSHIFT || key == VK_RSHIFT) return kShift;
  if (key == VK_SPACE) return kSpace;
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

constexpr bool HasVisibleTitleBar(const RECT& window, const RECT& work) {
  const LONG left = window.left > work.left ? window.left : work.left;
  const LONG right = window.right < work.right ? window.right : work.right;
  const LONG top = window.top > work.top ? window.top : work.top;
  const LONG title_bottom = window.top + 32;
  const LONG bottom = title_bottom < work.bottom ? title_bottom : work.bottom;
  return right - left >= 64 && bottom - top >= 24;
}

static_assert(HasVisibleTitleBar({100, 100, 900, 700}, {0, 0, 1920, 1080}));
static_assert(!HasVisibleTitleBar({2000, 100, 2800, 700}, {0, 0, 1920, 1080}));
static_assert(!HasVisibleTitleBar({100, -100, 900, 500}, {0, 0, 1920, 1080}));

void EnsureWindowVisible() {
  RECT bounds;
  if (!GetWindowRect(key_window, &bounds)) return;
  HMONITOR monitor = MonitorFromWindow(key_window, MONITOR_DEFAULTTONEAREST);
  MONITORINFO info = {sizeof(info)};
  if (!monitor || !GetMonitorInfoW(monitor, &info) ||
      HasVisibleTitleBar(bounds, info.rcWork)) return;
  const LONG work_width = info.rcWork.right - info.rcWork.left;
  const LONG work_height = info.rcWork.bottom - info.rcWork.top;
  const LONG width = bounds.right - bounds.left < work_width ? bounds.right - bounds.left : work_width;
  const LONG height = bounds.bottom - bounds.top < work_height ? bounds.bottom - bounds.top : work_height;
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
  if (message == WM_TIMER && wparam == kHudTimer) {
    InvalidateRect(hwnd, nullptr, FALSE);
    return 0;
  }
  if (message == WM_PAINT) {
    PAINTSTRUCT paint;
    HDC dc = BeginPaint(hwnd, &paint);
    RECT bounds; GetClientRect(hwnd, &bounds);
    HBRUSH bg = CreateSolidBrush(RGB(24, 24, 37));
    FillRect(dc, &bounds, bg); DeleteObject(bg);
    HBRUSH dot = CreateSolidBrush(hud_color);
    HGDIOBJ oldBrush = SelectObject(dc, dot);
    HGDIOBJ oldPen = SelectObject(dc, GetStockObject(NULL_PEN));
    if (!hud_success && !hud_writing) Ellipse(dc, 18, 25, 32, 39);
    SelectObject(dc, oldBrush); SelectObject(dc, oldPen); DeleteObject(dot);
    if (hud_writing) {
      const double angle = (GetTickCount64() % 960) * 6.283185307179586 / 960;
      HPEN pen = CreatePen(PS_SOLID, 2, RGB(245, 245, 250));
      HGDIOBJ previous = SelectObject(dc, pen);
      Arc(dc, 18, 25, 33, 40,
          25 + static_cast<int>(7 * std::cos(angle)),
          32 + static_cast<int>(7 * std::sin(angle)),
          25 + static_cast<int>(7 * std::cos(angle + 1.5)),
          32 + static_cast<int>(7 * std::sin(angle + 1.5)));
      SelectObject(dc, previous); DeleteObject(pen);
    }
    if (hud_success) {
      HPEN pen = CreatePen(PS_SOLID, 3, hud_color);
      HGDIOBJ previous = SelectObject(dc, pen);
      MoveToEx(dc, 18, 32, nullptr); LineTo(dc, 23, 37); LineTo(dc, 33, 26);
      SelectObject(dc, previous); DeleteObject(pen);
    }
    SetBkMode(dc, TRANSPARENT); SetTextColor(dc, RGB(245, 245, 250));
    HFONT font = CreateFontW(-17, 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
                            DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                            CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Segoe UI");
    HGDIOBJ oldFont = SelectObject(dc, font);
    RECT measured = {45, 0, bounds.right - 14, 0};
    DrawTextW(dc, hud_text.c_str(), -1, &measured, DT_LEFT | DT_WORDBREAK | DT_CALCRECT | DT_NOPREFIX);
    const int height = measured.bottom - measured.top;
    const LONG top = (bounds.bottom - height) / 2;
    RECT text = {45, top > 4 ? top : 4, bounds.right - 14, bounds.bottom - 4};
    DrawTextW(dc, hud_text.c_str(), -1, &text, DT_LEFT | DT_WORDBREAK | DT_END_ELLIPSIS | DT_NOPREFIX);
    SelectObject(dc, oldFont); DeleteObject(font);
    EndPaint(hwnd, &paint); return 0;
  }
  if (message == WM_MOUSEACTIVATE) return MA_NOACTIVATE;
  return DefWindowProc(hwnd, message, wparam, lparam);
}

bool CreateHud() {
  WNDCLASSW wc = {}; wc.lpfnWndProc = HudProc;
  wc.hInstance = GetModuleHandle(nullptr); wc.lpszClassName = L"AiDictatorHud";
  if (!RegisterClassW(&wc) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) return false;
  hud_window = CreateWindowExW(WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_LAYERED | WS_EX_TRANSPARENT,
      wc.lpszClassName, L"Dictation status", WS_POPUP, 0, 0, 340, 64, nullptr, nullptr, wc.hInstance, nullptr);
  if (!hud_window) return false;
  SetLayeredWindowAttributes(hud_window, 0, 240, LWA_ALPHA);
  SetWindowRgn(hud_window, CreateRoundRectRgn(0, 0, 341, 65, 32, 32), TRUE);
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
  SetWindowPos(hud_window, HWND_TOPMOST, work.left + (work.right - work.left - 340) / 2,
               work.bottom - 96, 340, 64, SWP_NOACTIVATE | SWP_SHOWWINDOW);
  InvalidateRect(hud_window, nullptr, TRUE);
}

void UpdateHudAnimation() {
  if (!hud_window) return;
  KillTimer(hud_window, kHudTimer);
  BOOL animations_enabled = TRUE;
  SystemParametersInfoW(SPI_GETCLIENTAREAANIMATION, 0, &animations_enabled, 0);
  if (hud_writing && IsWindowVisible(hud_window) && animations_enabled) {
    SetTimer(hud_window, kHudTimer, 60, nullptr);
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
  if (key == VK_ESCAPE && down && recording) {
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

  if (up && key == VK_SPACE && swallowed_space) {
    swallowed_space = false;
    return 1;
  }
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
    if (key == VK_SPACE) { swallowed_space = true; return 1; }
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
    : project_(project) {}

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
      unsigned hold = 0, translation = 0, hands_free = 0;
      if (recording || !read("hold", &hold) || !read("translation", &translation) ||
          !read("handsFree", &hands_free) || (hold & kSpace) ||
          (hold & (hold - 1)) == 0 || translation == hold ||
          (translation & hold) != hold || (translation & kSpace) ||
          hands_free != (hold | kSpace)) {
        result->Error("invalid_shortcut", "Shortcuts must use distinct supported combinations.");
      } else {
        KillTimer(key_window, kHoldTimer);
        hold_chord = hold; translation_chord = translation; hands_free_chord = hands_free;
        previous_keys = PhysicalKeys();
        hold_started = false; translating = false; chord_used = previous_keys != 0;
        result->Success(flutter::EncodableValue(true));
      }
    } else if (call.method_name() == "ensureWindowVisible") {
      EnsureWindowVisible(); result->Success();
    } else if (call.method_name() == "showHud") {
      ShowHud(); UpdateHudAnimation(); result->Success();
    } else if (call.method_name() == "hideHud") {
      if (hud_window) { KillTimer(hud_window, kHudTimer); ShowWindow(hud_window, SW_HIDE); }
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
        hud_success = s && *s == "success";
        hud_writing = s && *s == "writing";
        if (s && *s == "preparing") {
          hud_text = L"Please wait before speaking..."; hud_color = RGB(255, 194, 90);
        } else if (s && *s == "listening") {
          hud_text = L"Speak now  " + std::to_wstring(n ? *n / 60 : 0) + L":" + ((n && *n % 60 >= 10) ? L"" : L"0") + std::to_wstring(n ? *n % 60 : 0);
          hud_color = RGB(255, 104, 104);
        } else if (s && *s == "writing") { hud_text = L"Turning speech into text..."; hud_color = RGB(101, 210, 238); }
        else if (s && *s == "success") { hud_text = L"Done"; hud_color = RGB(105, 220, 150); }
        else if (s && *s == "error") { hud_text = m && !m->empty() ? Wide(*m) : L"Error occurred"; hud_color = RGB(255, 194, 90); }
        UpdateHudAnimation();
        if (hud_window) InvalidateRect(hud_window, nullptr, TRUE);
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
