#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <string>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  const bool activation = wcsstr(command_line, L"-ToastActivated") != nullptr;
  const bool verification = wcsstr(command_line, L"--verification") != nullptr;
  const bool preview = std::string(FLUTTER_VERSION).find("-preview") != std::string::npos;
  const wchar_t* title = preview ? L"日程表 · 本地预览" : verification ? L"日程表 · 验证" : L"日程表";
  HANDLE app_mutex = CreateMutexW(nullptr, FALSE, preview ? L"Local\\WarmCalendar.Planner.Preview" : verification ? L"Local\\WarmCalendar.Planner.Verification" : L"Local\\WarmCalendar.Planner.Desktop");
  if (!activation && GetLastError() == ERROR_ALREADY_EXISTS) {
    if (const auto existing = FindWindowW(nullptr, title)) {
      ShowWindow(existing, SW_RESTORE);
      SetForegroundWindow(existing);
    }
    CloseHandle(app_mutex);
    return EXIT_SUCCESS;
  }
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(title, origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (app_mutex) CloseHandle(app_mutex);
  return EXIT_SUCCESS;
}
