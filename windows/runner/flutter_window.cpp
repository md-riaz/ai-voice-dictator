#include "flutter_window.h"

#include <optional>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"

namespace {
std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> keys;
HHOOK hook = nullptr;
HWND key_window = nullptr;
HWND hud_window = nullptr;
std::wstring hud_text = L"Listening...";
COLORREF hud_color = RGB(255, 104, 104);
bool ctrl = false, win = false, alt = false, space = false;
bool hold_started = false, chord_used = false, recording = false;
constexpr UINT_PTR kHoldTimer = 102;

std::wstring Wide(const std::string& text) {
  if (text.empty()) return {};
  int size = MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0);
  std::wstring out(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), out.data(), size);
  return out;
}

LRESULT CALLBACK HudProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == WM_PAINT) {
    PAINTSTRUCT paint;
    HDC dc = BeginPaint(hwnd, &paint);
    RECT bounds; GetClientRect(hwnd, &bounds);
    HBRUSH bg = CreateSolidBrush(RGB(24, 24, 37));
    FillRect(dc, &bounds, bg); DeleteObject(bg);
    HBRUSH dot = CreateSolidBrush(hud_color);
    HGDIOBJ oldBrush = SelectObject(dc, dot);
    HGDIOBJ oldPen = SelectObject(dc, GetStockObject(NULL_PEN));
    Ellipse(dc, 18, 24, 32, 38);
    SelectObject(dc, oldBrush); SelectObject(dc, oldPen); DeleteObject(dot);
    SetBkMode(dc, TRANSPARENT); SetTextColor(dc, RGB(245, 245, 250));
    HFONT font = CreateFontW(-17, 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
                            DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                            CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Segoe UI");
    HGDIOBJ oldFont = SelectObject(dc, font);
    RECT text = {45, 8, bounds.right - 14, bounds.bottom - 8};
    DrawTextW(dc, hud_text.c_str(), -1, &text, DT_LEFT | DT_VCENTER | DT_WORDBREAK | DT_END_ELLIPSIS | DT_NOPREFIX);
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
  RECT work; SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0);
  SetWindowPos(hud_window, HWND_TOPMOST, work.left + (work.right - work.left - 340) / 2,
               work.bottom - 96, 340, 64, SWP_NOACTIVATE | SWP_SHOWWINDOW);
  InvalidateRect(hud_window, nullptr, TRUE);
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
  if (key == VK_LCONTROL || key == VK_RCONTROL || key == VK_CONTROL) ctrl = down;
  if (key == VK_LWIN || key == VK_RWIN) win = down;
  if (key == VK_LMENU || key == VK_RMENU || key == VK_MENU) {
    const bool was_alt = alt;
    alt = down;
    if (down && !was_alt && ctrl && win && !chord_used) {
      KillTimer(key_window, kHoldTimer);
      Emit(hold_started ? "switchTranslation" : "translationStart");
      hold_started = true;
    } else if (up && was_alt && hold_started && ctrl && win) {
      hold_started = false;
      chord_used = true;
      Emit("holdStop");
    }
  }
  if (key == VK_SPACE) {
    const bool was_space = space;
    space = down;
    if (down && !was_space && ctrl && win) {
      KillTimer(key_window, kHoldTimer);
      Emit("handsFree");
      hold_started = false;
      chord_used = true;
      return 1;
    }
    if (up && chord_used) return 1;
  }
  if (ctrl && win && !alt && !space && !hold_started && !chord_used) {
    SetTimer(key_window, kHoldTimer, 180, nullptr);
  }
  if ((!ctrl || !win) && (key == VK_LCONTROL || key == VK_RCONTROL || key == VK_CONTROL || key == VK_LWIN || key == VK_RWIN)) {
    KillTimer(key_window, kHoldTimer);
    if (hold_started) {
      hold_started = false;
      Emit("holdStop");
    }
    chord_used = false;
  }
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
    } else if (call.method_name() == "showHud") {
      ShowHud(); result->Success();
    } else if (call.method_name() == "hideHud") {
      if (hud_window) ShowWindow(hud_window, SW_HIDE);
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
        if (s && *s == "listening") {
          hud_text = L"Listening...  " + std::to_wstring(n ? *n / 60 : 0) + L":" + ((n && *n % 60 >= 10) ? L"" : L"0") + std::to_wstring(n ? *n % 60 : 0);
          hud_color = RGB(255, 104, 104);
        } else if (s && *s == "writing") { hud_text = L"Writing..."; hud_color = RGB(101, 210, 238); }
        else if (s && *s == "success") { hud_text = L"Inserted!"; hud_color = RGB(105, 220, 150); }
        else if (s && *s == "error") { hud_text = m && !m->empty() ? Wide(*m) : L"Error occurred"; hud_color = RGB(255, 194, 90); }
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
  if (hud_window) DestroyWindow(hud_window);
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
        if (ctrl && win && !alt && !space && !chord_used && !hold_started) {
          hold_started = true;
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
