#include "flutter_window.h"

#include <optional>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"

namespace {
std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> keys;
HHOOK hook = nullptr;
HWND key_window = nullptr;
bool ctrl = false, win = false, alt = false, space = false;
bool hold_started = false, chord_used = false, recording = false;
constexpr UINT_PTR kHoldTimer = 102;

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
