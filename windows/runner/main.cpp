#include <algorithm>

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter_windows.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
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

  // Pick a useful initial size for the available work area and center it.
  // Win32Window::Create scales these logical dimensions for the target DPI.
  RECT work_area{};
  if (!SystemParametersInfo(SPI_GETWORKAREA, 0, &work_area, 0)) {
    work_area = {0, 0, GetSystemMetrics(SM_CXSCREEN),
                 GetSystemMetrics(SM_CYSCREEN)};
  }
  const POINT monitor_point = {
      static_cast<LONG>(work_area.left + 1),
      static_cast<LONG>(work_area.top + 1)};
  const HMONITOR monitor =
      MonitorFromPoint(monitor_point, MONITOR_DEFAULTTONEAREST);
  const UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  const double scale = dpi == 0 ? 1.0 : static_cast<double>(dpi) / 96.0;
  const int work_width =
      static_cast<int>((work_area.right - work_area.left) / scale);
  const int work_height =
      static_cast<int>((work_area.bottom - work_area.top) / scale);

  const unsigned int width = static_cast<unsigned int>(
      std::min(1280, std::max(780, work_width - 48)));
  const unsigned int height = static_cast<unsigned int>(
      std::min(720, std::max(520, work_height - 64)));
  const unsigned int x = static_cast<unsigned int>(
      std::max(0, (work_width - static_cast<int>(width)) / 2));
  const unsigned int y = static_cast<unsigned int>(
      std::max(0, (work_height - static_cast<int>(height)) / 2));

  Win32Window::Point origin(x, y);
  Win32Window::Size size(width, height);
  if (!window.Create(L"Поколение", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
