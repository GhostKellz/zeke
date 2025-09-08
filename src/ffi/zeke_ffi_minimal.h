#ifndef ZEKE_FFI_MINIMAL_H
#define ZEKE_FFI_MINIMAL_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// Forward declarations for opaque types
typedef struct ZekeHandle ZekeHandle;
typedef struct ZekeConfigHandle ZekeConfigHandle;

// Error codes
typedef enum {
    ZEKE_SUCCESS = 0,
    ZEKE_INITIALIZATION_FAILED = -1,
    ZEKE_AUTHENTICATION_FAILED = -2,
    ZEKE_NETWORK_ERROR = -4,
    ZEKE_MEMORY_ERROR = -8,
    ZEKE_INVALID_PARAMETER = -9,
} ZekeErrorCode;

// Basic config structure
typedef struct {
    const char* base_url;
    const char* api_key;
    int32_t provider;
    const char* model_name;
    float temperature;
    uint32_t max_tokens;
    bool stream;
    bool enable_gpu;
    bool enable_fallback;
    uint32_t timeout_ms;
} ZekeConfig;

// Basic response structure
typedef struct {
    const char* content;
    int32_t provider_used;
    uint32_t tokens_used;
    uint32_t response_time_ms;
    ZekeErrorCode error_code;
    const char* error_message;
} ZekeResponse;

// Core FFI functions
ZekeHandle* zeke_init(const ZekeConfig* config);
ZekeErrorCode zeke_chat(ZekeHandle* handle, const char* message, ZekeResponse* response_out);
ZekeErrorCode zeke_test_auth(ZekeHandle* handle, int32_t provider);
void zeke_free_response(ZekeResponse* response);
void zeke_destroy(ZekeHandle* handle);
const char* zeke_version(void);
ZekeErrorCode zeke_health_check(ZekeHandle* handle);
const char* zeke_get_last_error(void);

#ifdef __cplusplus
}
#endif

#endif // ZEKE_FFI_MINIMAL_H