#include "flutter_window.h"

#include <optional>
#include <dwmapi.h>

#include "flutter/generated_plugin_registrant.h"

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
  chrome_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "korrekta/window",
      &flutter::StandardMethodCodec::GetInstance());
  chrome_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() != "colors") {
      result->NotImplemented();
      return;
    }
    const auto* colors = std::get_if<flutter::EncodableList>(call.arguments());
    if (!colors || colors->size() != 2) {
      result->Error("arguments", "Нужны два цвета");
      return;
    }
    const auto* background = std::get_if<int32_t>(&(*colors)[0]);
    const auto* foreground = std::get_if<int32_t>(&(*colors)[1]);
    if (!background || !foreground) {
      result->Error("arguments", "Нужны целочисленные цвета");
      return;
    }
    const COLORREF caption = RGB((*background >> 16) & 255, (*background >> 8) & 255, *background & 255);
    const COLORREF text = RGB((*foreground >> 16) & 255, (*foreground >> 8) & 255, *foreground & 255);
    DwmSetWindowAttribute(GetHandle(), 35, &caption, sizeof(caption));
    DwmSetWindowAttribute(GetHandle(), 36, &text, sizeof(text));
    result->Success();
  });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  chrome_channel_ = nullptr;
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
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
