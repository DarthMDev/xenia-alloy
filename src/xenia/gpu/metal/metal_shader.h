/**
 ******************************************************************************
 * Xenia : Xbox 360 Emulator Research Project                                 *
 ******************************************************************************
 * Copyright 2026 Ben Vanik. All rights reserved.                             *
 * Released under the BSD license - see LICENSE in the root for more details. *
 ******************************************************************************
 */

#ifndef XENIA_GPU_METAL_METAL_SHADER_H_
#define XENIA_GPU_METAL_METAL_SHADER_H_

#include <atomic>
#include <string>
#include <vector>

#include "xenia/gpu/dxbc_shader.h"
#include "xenia/ui/metal/metal_api.h"

namespace xe {
namespace gpu {
namespace metal {

class DxbcToDxilConverter;
class MetalShaderConverter;

class MetalShader : public DxbcShader {
 public:
  class MetalTranslation : public DxbcTranslation {
   public:
    MetalTranslation(MetalShader& shader, uint64_t modification)
        : DxbcTranslation(shader, modification) {}
    ~MetalTranslation();

    // Convert DXBC -> DXIL -> Metal IR using the shader converter
    bool TranslateToMetal(MTL::Device* device,
                          DxbcToDxilConverter& dxbc_converter,
                          MetalShaderConverter& metal_converter);

    // Get the Metal library (contains compiled shader)
    MTL::Library* metal_library() const { return metal_library_; }

    // Get the Metal function (shader entry point)
    MTL::Function* metal_function() const { return metal_function_; }

    // Load the metallib from the disk shader cache if present (cheap).
    bool TryLoadFromDiskCache(MTL::Device* device);

    // Background translation state (metal_async_shader_translation).
    enum class AsyncState : uint32_t { kNone, kPending, kDone };
    AsyncState async_state() const {
      return async_state_.load(std::memory_order_acquire);
    }
    // Returns false if already queued or done.
    bool BeginAsyncTranslation() {
      AsyncState expected = AsyncState::kNone;
      return async_state_.compare_exchange_strong(expected,
                                                  AsyncState::kPending);
    }
    void EndAsyncTranslation(bool succeeded) {
      async_failed_ = !succeeded;
      async_state_.store(AsyncState::kDone, std::memory_order_release);
    }
    bool async_failed() const { return async_failed_; }

    // Check if translation succeeded
    bool is_valid() const {
      return async_state() != AsyncState::kPending &&
             metal_function_ != nullptr;
    }

    // Get intermediate data for debugging
    const std::vector<uint8_t>& dxil_data() const { return dxil_data_; }
    const std::vector<uint8_t>& metallib_data() const { return metallib_data_; }
    const std::string& function_name() const { return function_name_; }

   private:
    MTL::Library* metal_library_ = nullptr;
    MTL::Function* metal_function_ = nullptr;
    std::vector<uint8_t> dxil_data_;
    std::vector<uint8_t> metallib_data_;
    std::string function_name_;
    std::atomic<AsyncState> async_state_{AsyncState::kNone};
    bool async_failed_ = false;
  };

  MetalShader(xenos::ShaderType shader_type, uint64_t ucode_data_hash,
              const uint32_t* ucode_dwords, size_t ucode_dword_count,
              std::endian ucode_source_endian = std::endian::big);

  // For owning subsystem like the pipeline cache, accessors for unique
  // identifiers (used instead of hashes to make sure collisions can't happen)
  // of binding layouts used by the shader, for invalidation if a shader with an
  // incompatible layout was bound.
  size_t GetTextureBindingLayoutUserUID() const {
    return texture_binding_layout_user_uid_;
  }
  size_t GetSamplerBindingLayoutUserUID() const {
    return sampler_binding_layout_user_uid_;
  }
  // Modifications of the same shader can be translated on different threads.
  // The "set" function must only be called if "enter" returned true - these are
  // set up only once.
  bool EnterBindingLayoutUserUIDSetup() {
    return !binding_layout_user_uids_set_up_.test_and_set();
  }
  void SetTextureBindingLayoutUserUID(size_t uid) {
    texture_binding_layout_user_uid_ = uid;
  }
  void SetSamplerBindingLayoutUserUID(size_t uid) {
    sampler_binding_layout_user_uid_ = uid;
  }

 protected:
  Translation* CreateTranslationInstance(uint64_t modification) override;

 private:
  std::atomic_flag binding_layout_user_uids_set_up_ = ATOMIC_FLAG_INIT;
  size_t texture_binding_layout_user_uid_ = 0;
  size_t sampler_binding_layout_user_uid_ = 0;
};

}  // namespace metal
}  // namespace gpu
}  // namespace xe

#endif  // XENIA_GPU_METAL_METAL_SHADER_H_
