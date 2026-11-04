#include <windows.h>
#include <shellapi.h>
#include <shobjidl.h>
#include <winrt/Windows.Data.Xml.Dom.h>
#include <winrt/Windows.UI.Notifications.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <flutter/standard_method_codec.h>
#include <chrono>
#include <string>
#include <cstdio>
#include "notification_bridge.h"

namespace {
const bool kPreview = std::string(FLUTTER_VERSION).find("-preview") != std::string::npos;
const bool kVerification = wcsstr(GetCommandLineW(), L"--verification") != nullptr;
const wchar_t* kAppId = kPreview ? L"WarmCalendar.Planner.Preview" : kVerification ? L"WarmCalendar.Planner.Verification" : L"WarmCalendar.Planner.Desktop";
const wchar_t* kClsid = kPreview ? L"{96e55b26-0749-4543-ae4e-4c8535468812}" : kVerification ? L"{96e55b26-0749-4543-ae4e-4c8535468811}" : L"{96e55b26-0749-4543-ae4e-4c8535468810}";
const wchar_t* kStartupName = kPreview ? L"WarmCalendarPreview" : kVerification ? L"WarmCalendarVerification" : L"WarmCalendar";
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;
using namespace winrt::Windows::UI::Notifications;

void SetString(HKEY root, const std::wstring& path, const wchar_t* name,
               const std::wstring& value) {
  HKEY key;
  winrt::check_win32(RegCreateKeyExW(root, path.c_str(), 0, nullptr, 0,
                                  KEY_SET_VALUE, nullptr, &key, nullptr));
  const auto code = RegSetValueExW(key, name, 0, REG_SZ,
      reinterpret_cast<const BYTE*>(value.c_str()),
      static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t)));
  RegCloseKey(key);
  winrt::check_win32(code);
}
std::wstring ExePath() {
  wchar_t buffer[32768];
  const auto length = GetModuleFileNameW(nullptr, buffer, 32768);
  if (!length || length == 32768) throw winrt::hresult_error(E_FAIL);
  return std::wstring(buffer, length);
}
ToastNotifier Notifier() { return ToastNotificationManager::CreateToastNotifier(kAppId); }
int64_t Number(const Value& value) {
  if (const auto intValue = std::get_if<int32_t>(&value)) return *intValue;
  return std::get<int64_t>(value);
}
}

std::unique_ptr<flutter::MethodChannel<Value>>
CreateNotificationBridge(flutter::BinaryMessenger* messenger) {
  auto channel = std::make_unique<flutter::MethodChannel<Value>>(
      messenger, "warm_calendar/windows", &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([](const auto& call, auto result) {
    try {
      const auto& method = call.method_name();
      if (method == "registerActivation") {
        winrt::check_hresult(SetCurrentProcessExplicitAppUserModelID(kAppId));
        // Per-user COM server allows a toast click to reopen the executable.
        SetString(HKEY_CURRENT_USER, std::wstring(L"Software\\Classes\\CLSID\\") +
            kClsid + L"\\LocalServer32", nullptr, L"\"" + ExePath() + L"\" -ToastActivated" + (kVerification ? L" --verification" : L""));
        result->Success();
      } else if (method == "permission") {
        try {
          result->Success(Value(Notifier().Setting() == NotificationSetting::Enabled ? "granted" : "denied"));
        } catch (const winrt::hresult_error& error) {
          // Windows may not create the per-app notification settings entry
          // until its first toast is delivered. This is not a denial; queue and
          // delivery failures must still propagate through their own calls.
          if (error.code().value != HRESULT_FROM_WIN32(ERROR_NOT_FOUND)) throw;
          result->Success(Value("unregistered"));
        }
      } else if (method == "openSettings") {
        const auto code = reinterpret_cast<INT_PTR>(ShellExecuteW(nullptr, L"open",
            L"ms-settings:notifications", nullptr, nullptr, SW_SHOWNORMAL));
        if (code <= 32) throw winrt::hresult_error(E_FAIL);
        result->Success();
      } else if (method == "startupEnabled") {
        DWORD bytes = 0;
        const auto code = RegGetValueW(HKEY_CURRENT_USER,
            L"Software\\Microsoft\\Windows\\CurrentVersion\\Run",
            kStartupName,
            RRF_RT_REG_SZ, nullptr, nullptr, &bytes);
        if (code != ERROR_SUCCESS && code != ERROR_FILE_NOT_FOUND) {
          winrt::check_win32(code);
        }
        result->Success(Value(code == ERROR_SUCCESS && bytes > sizeof(wchar_t)));
      } else if (method == "startup") {
        const auto enabled = std::get<bool>(*call.arguments());
        constexpr auto path = L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
        if (enabled) {
          SetString(HKEY_CURRENT_USER, path, kStartupName, L"\"" + ExePath() + L"\" --tray" + (kVerification ? L" --verification" : L""));
        } else {
          HKEY key;
          if (RegOpenKeyExW(HKEY_CURRENT_USER, path, 0, KEY_SET_VALUE, &key) == ERROR_SUCCESS) {
            const auto code = RegDeleteValueW(key, kStartupName);
            RegCloseKey(key);
            if (code != ERROR_SUCCESS && code != ERROR_FILE_NOT_FOUND) winrt::check_win32(code);
          }
        }
        result->Success();
      } else if (method == "pending") {
        flutter::EncodableList ids;
        for (const auto& item : Notifier().GetScheduledToastNotifications()) {
          ids.emplace_back(std::stoi(winrt::to_string(item.Tag())));
        }
        result->Success(Value(ids));
      } else if (method == "schedule" || method == "show") {
        const auto& args = std::get<Map>(*call.arguments());
        const auto id = std::get<std::string>(args.at(Value("id")));
        winrt::Windows::Data::Xml::Dom::XmlDocument doc;
        doc.LoadXml(winrt::to_hstring(std::get<std::string>(args.at(Value("xml")))));
        auto notifier = Notifier();
        if (method == "schedule") {
          const auto ms = Number(args.at(Value("at")));
          ScheduledToastNotification notification(doc, winrt::clock::from_time_t(static_cast<time_t>(ms / 1000)));
          notification.Tag(winrt::to_hstring(id));
          const auto expires = Number(args.at(Value("expires")));
          notification.ExpirationTime(winrt::clock::from_time_t(static_cast<time_t>(expires / 1000)));
          notifier.AddToSchedule(notification);
        } else {
          ToastNotification notification(doc);
          notification.Tag(winrt::to_hstring(id));
          notifier.Show(notification);
        }
        result->Success();
      } else if (method == "cancel") {
        const auto id = winrt::to_hstring(std::get<std::string>(*call.arguments()));
        auto notifier = Notifier();
        for (const auto& notification : notifier.GetScheduledToastNotifications()) {
          if (notification.Tag() == id) notifier.RemoveFromSchedule(notification);
        }
        result->Success();
      } else {
        result->NotImplemented();
      }
    } catch (const winrt::hresult_error& error) {
      char code[16];
      snprintf(code, sizeof(code), "0x%08lX", static_cast<unsigned long>(error.code().value));
      result->Error("windows_notification", call.method_name() + ": " + code + " " + winrt::to_string(error.message()));
    } catch (const std::exception& error) {
      result->Error("windows_notification", error.what());
    }
  });
  return channel;
}
