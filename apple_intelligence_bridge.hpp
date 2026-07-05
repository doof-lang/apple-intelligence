#pragma once

#include <cstdlib>
#include <memory>
#include <string>
#include <utility>
#include <vector>

#include "doof_runtime.hpp"

extern "C" {
    typedef char* (*ai_tool_callback_t)(void* context, const char* argsJson, char** outError);

    void  ai_free_string(char* str);
    void* ai_session_create(const char* instructions, char** outError);
    void  ai_session_release(void* session);
    char* ai_session_respond(void* session, const char* prompt, char** outError);
    char* ai_session_transcript_json(void* session, char** outError);
    int   ai_session_add_tool(
        void* session,
        const char* name,
        const char* description,
        const char* inputSchemaJson,
        void* callbackContext,
        ai_tool_callback_t callback,
        char** outError
    );
}

namespace apple_intelligence_detail {

inline doof::Result<std::string, std::string> wrap_string_result(char* raw, char* error) {
    if (raw) {
        std::string value(raw);
        ai_free_string(raw);
        return doof::Result<std::string, std::string>::success(std::move(value));
    }

    std::string message(error ? error : "unknown Apple Intelligence error");
    if (error) {
        ai_free_string(error);
    }
    return doof::Result<std::string, std::string>::failure(std::move(message));
}

inline doof::Result<void, std::string> wrap_void_result(int ok, char* error) {
    if (ok != 0) {
        return doof::Result<void, std::string>::success();
    }

    std::string message(error ? error : "unknown Apple Intelligence error");
    if (error) {
        ai_free_string(error);
    }
    return doof::Result<void, std::string>::failure(std::move(message));
}

struct ToolCallback {
    doof::callback<doof::Result<std::string, std::string>(std::string)> invoke;

    explicit ToolCallback(doof::callback<doof::Result<std::string, std::string>(std::string)> callback)
        : invoke(std::move(callback)) {}
};

inline char* call_tool(void* context, const char* argsJson, char** outError) {
    auto* callback = static_cast<ToolCallback*>(context);
    if (callback == nullptr) {
        if (outError) {
            *outError = strdup("missing Doof tool callback");
        }
        return nullptr;
    }

    try {
        doof::detail::ActiveActorScope active(&doof::detail::ApplicationDomain::shared());
        auto result = doof::detail::call_callback_unchecked(
            callback->invoke,
            std::string(argsJson ? argsJson : "null")
        );
        if (result.isSuccess()) {
            return strdup(result.value().c_str());
        }
        if (outError) {
            *outError = strdup(result.error().c_str());
        }
        return nullptr;
    } catch (const doof::Panic& e) {
        if (outError) {
            *outError = strdup(e.what());
        }
        return nullptr;
    } catch (const std::exception& e) {
        if (outError) {
            *outError = strdup(e.what());
        }
        return nullptr;
    } catch (...) {
        if (outError) {
            *outError = strdup("unknown Doof tool callback error");
        }
        return nullptr;
    }
}

} // namespace apple_intelligence_detail

class NativeAppleIntelligenceSession {
public:
    explicit NativeAppleIntelligenceSession(const std::string& instructions) {
        char* error = nullptr;
        handle_ = ai_session_create(instructions.c_str(), &error);
        if (!handle_) {
            initError_ = error ? error : "failed to create Apple Intelligence session";
            if (error) {
                ai_free_string(error);
            }
        }
    }

    ~NativeAppleIntelligenceSession() {
        if (handle_) {
            ai_session_release(handle_);
            handle_ = nullptr;
        }
    }

    doof::Result<std::string, std::string> respond(const std::string& prompt) const {
        if (!handle_) {
            return doof::Result<std::string, std::string>::failure(initError_);
        }
        char* error = nullptr;
        char* result = ai_session_respond(handle_, prompt.c_str(), &error);
        return apple_intelligence_detail::wrap_string_result(result, error);
    }

    doof::Result<std::string, std::string> transcriptJson() const {
        if (!handle_) {
            return doof::Result<std::string, std::string>::failure(initError_);
        }
        char* error = nullptr;
        char* result = ai_session_transcript_json(handle_, &error);
        return apple_intelligence_detail::wrap_string_result(result, error);
    }

    doof::Result<void, std::string> addTool(
        const std::string& name,
        const std::string& description,
        const std::string& inputSchemaJson,
        doof::callback<doof::Result<std::string, std::string>(std::string)> invoke
    ) {
        if (!handle_) {
            return doof::Result<void, std::string>::failure(initError_);
        }

        auto callback = std::make_unique<apple_intelligence_detail::ToolCallback>(std::move(invoke));
        char* error = nullptr;
        int ok = ai_session_add_tool(
            handle_,
            name.c_str(),
            description.c_str(),
            inputSchemaJson.c_str(),
            callback.get(),
            apple_intelligence_detail::call_tool,
            &error
        );

        auto result = apple_intelligence_detail::wrap_void_result(ok, error);
        if (result.isSuccess()) {
            callbacks_.push_back(std::move(callback));
        }
        return result;
    }

private:
    void* handle_ = nullptr;
    std::string initError_;
    std::vector<std::unique_ptr<apple_intelligence_detail::ToolCallback>> callbacks_;
};

inline std::shared_ptr<NativeAppleIntelligenceSession>
createNativeAppleIntelligenceSession(const std::string& instructions) {
    return std::make_shared<NativeAppleIntelligenceSession>(instructions);
}
