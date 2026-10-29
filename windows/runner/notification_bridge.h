#pragma once
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>
#include <flutter/binary_messenger.h>
#include <memory>

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
CreateNotificationBridge(flutter::BinaryMessenger* messenger);
