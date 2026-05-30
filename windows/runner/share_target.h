#ifndef RUNNER_SHARE_TARGET_H_
#define RUNNER_SHARE_TARGET_H_

#include <string>
#include <vector>

// If the app was activated as a Windows Share target, appends shared file/folder
// paths to the Dart entrypoint arguments so Flutter can pick them up.
void AppendShareTargetArgs(std::vector<std::string>* args);

#endif  // RUNNER_SHARE_TARGET_H_

