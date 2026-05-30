#include "share_target.h"

#include <winrt/Windows.ApplicationModel.h>
#include <winrt/Windows.ApplicationModel.Activation.h>
#include <winrt/Windows.ApplicationModel.DataTransfer.ShareTarget.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Storage.h>

#include "utils.h"

void AppendShareTargetArgs(std::vector<std::string>* args) {
  if (args == nullptr) return;

  try {
    const auto activated =
        winrt::Windows::ApplicationModel::AppInstance::GetActivatedEventArgs();
    if (activated == nullptr) return;

    if (activated.Kind() != winrt::Windows::ApplicationModel::Activation::ActivationKind::ShareTarget) {
      return;
    }

    const auto shareArgs =
        activated.as<winrt::Windows::ApplicationModel::Activation::ShareTargetActivatedEventArgs>();
    const auto operation = shareArgs.ShareOperation();
    const auto items = operation.Data().GetStorageItemsAsync().get();

    for (const auto& item : items) {
      const auto path = item.Path();
      if (path.empty()) continue;

      auto utf8 = Utf8FromUtf16(path.c_str());
      if (!utf8.empty()) args->push_back(std::move(utf8));
    }

    // Tell Windows we're done so the Share UI can close promptly.
    operation.ReportCompleted();
  } catch (const winrt::hresult_error&) {
    // Likely unpackaged execution (no package identity) or non-share activation.
  } catch (...) {
    // Best-effort only; never block app startup.
  }
}
