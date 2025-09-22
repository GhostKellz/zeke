#ifndef ZEKE_FFI_H
#define ZEKE_FFI_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>
#include <stdbool.h>

// ============================================================================
// Type Definitions
// ============================================================================

// Opaque handles for Rust integration
typedef struct ZekeHandle ZekeHandle;
typedef struct ZekeConfigHandle ZekeConfigHandle; 
typedef struct ZekeAuthHandle ZekeAuthHandle;
typedef struct ZekeProviderHandle ZekeProviderHandle;
typedef struct ZekeStreamHandle ZekeStreamHandle;
typedef struct ZekeGhostLLMHandle ZekeGhostLLMHandle;

// Error codes
typedef enum {
    ZEKE_SUCCESS = 0,
    ZEKE_INITIALIZATION_FAILED = -1,
    ZEKE_AUTHENTICATION_FAILED = -2,
    ZEKE_CONFIG_LOAD_FAILED = -3,
    ZEKE_NETWORK_ERROR = -4,
    ZEKE_INVALID_MODEL = -5,
    ZEKE_TOKEN_EXCHANGE_FAILED = -6,
    ZEKE_UNEXPECTED_RESPONSE = -7,
    ZEKE_MEMORY_ERROR = -8,
    ZEKE_INVALID_PARAMETER = -9,
    ZEKE_PROVIDER_UNAVAILABLE = -10,
    ZEKE_STREAMING_FAILED = -11
} ZekeErrorCode;

// Provider types
typedef enum {
    ZEKE_PROVIDER_COPILOT = 0,
    ZEKE_PROVIDER_CLAUDE = 1,
    ZEKE_PROVIDER_OPENAI = 2,
    ZEKE_PROVIDER_OLLAMA = 3,
    ZEKE_PROVIDER_GHOSTLLM = 4
} ZekeProvider;

// Configuration structure
typedef struct {
    const char* base_url;
    const char* api_key;
    int provider;
    const char* model_name;
    float temperature;
    uint32_t max_tokens;
    bool stream;
    bool enable_gpu;
    bool enable_fallback;
    uint32_t timeout_ms;
} ZekeConfig;

// Response structure
typedef struct {
    const char* content;
    int provider_used;
    uint32_t tokens_used;
    uint32_t response_time_ms;
    ZekeErrorCode error_code;
    const char* error_message;
} ZekeResponse;

// Streaming chunk
typedef struct {
    const char* content;
    bool is_final;
    uint32_t chunk_index;
    uint32_t total_chunks;
} ZekeStreamChunk;

// GPU information
typedef struct {
    const char* device_name;
    uint64_t memory_used_mb;
    uint64_t memory_total_mb;
    uint8_t utilization_percent;
    uint8_t temperature_celsius;
    uint32_t power_watts;
} ZekeGpuInfo;

// Provider status
typedef struct {
    int provider;
    bool is_healthy;
    uint32_t response_time_ms;
    float error_rate;
    uint32_t requests_per_minute;
} ZekeProviderStatus;

// Callback types
typedef void (*ZekeStreamCallback)(const ZekeStreamChunk* chunk, void* user_data);
typedef void (*ZekeAsyncCallback)(const ZekeResponse* response, void* user_data);

// ============================================================================
// Core Zeke Instance Management
// ============================================================================

/**
 * Initialize a new Zeke instance with the given configuration
 * @param config Configuration parameters for Zeke
 * @return Handle to Zeke instance or NULL on failure
 */
ZekeHandle* zeke_init(const ZekeConfig* config);

/**
 * Clean up and destroy a Zeke instance
 * @param handle Zeke instance handle
 */
void zeke_destroy(ZekeHandle* handle);

/**
 * Get the version string of Zeke
 * @return Version string
 */
const char* zeke_version(void);

// ============================================================================
// Chat and Completion API
// ============================================================================

/**
 * Send a chat message and get a response
 * @param handle Zeke instance handle
 * @param message Input message
 * @param response_out Output response structure
 * @return Error code
 */
ZekeErrorCode zeke_chat(ZekeHandle* handle, const char* message, ZekeResponse* response_out);

/**
 * Send a streaming chat message with callback for chunks
 * @param handle Zeke instance handle
 * @param message Input message
 * @param callback Callback function for stream chunks
 * @param user_data User data passed to callback
 * @return Error code
 */
ZekeErrorCode zeke_chat_stream(
    ZekeHandle* handle,
    const char* message,
    ZekeStreamCallback callback,
    void* user_data
);

/**
 * Free memory allocated for a ZekeResponse
 * @param response Response to free
 */
void zeke_free_response(ZekeResponse* response);

// ============================================================================
// Authentication Management
// ============================================================================

/**
 * Set authentication token for a provider
 * @param handle Zeke instance handle
 * @param provider Provider type
 * @param token Authentication token
 * @return Error code
 */
ZekeErrorCode zeke_set_auth_token(ZekeHandle* handle, int provider, const char* token);

/**
 * Test authentication for a provider
 * @param handle Zeke instance handle
 * @param provider Provider type
 * @return Error code (ZEKE_SUCCESS if authenticated)
 */
ZekeErrorCode zeke_test_auth(ZekeHandle* handle, int provider);

// ============================================================================
// Provider Management
// ============================================================================

/**
 * Switch to a different provider
 * @param handle Zeke instance handle
 * @param provider Provider to switch to
 * @return Error code
 */
ZekeErrorCode zeke_switch_provider(ZekeHandle* handle, int provider);

/**
 * Get status of all providers
 * @param handle Zeke instance handle
 * @param status_array Array to fill with status information
 * @param array_size Size of the array
 * @param actual_count Actual number of providers
 * @return Error code
 */
ZekeErrorCode zeke_get_provider_status(
    ZekeHandle* handle,
    ZekeProviderStatus* status_array,
    size_t array_size,
    size_t* actual_count
);

// ============================================================================
// GhostLLM GPU Integration
// ============================================================================

/**
 * Initialize GhostLLM GPU client
 * @param handle Zeke instance handle
 * @param base_url GhostLLM server URL
 * @param enable_gpu Whether to enable GPU acceleration
 * @return Error code
 */
ZekeErrorCode zeke_ghostllm_init(ZekeHandle* handle, const char* base_url, bool enable_gpu);

/**
 * Get GPU information from GhostLLM
 * @param handle Zeke instance handle
 * @param gpu_info Output GPU information
 * @return Error code
 */
ZekeErrorCode zeke_ghostllm_get_gpu_info(ZekeHandle* handle, ZekeGpuInfo* gpu_info);

/**
 * Free GPU info memory
 * @param gpu_info GPU info to free
 */
void zeke_free_gpu_info(ZekeGpuInfo* gpu_info);

/**
 * Run GhostLLM benchmark
 * @param handle Zeke instance handle
 * @param model_name Model to benchmark
 * @param batch_size Batch size for benchmark
 * @return Error code
 */
ZekeErrorCode zeke_ghostllm_benchmark(ZekeHandle* handle, const char* model_name, uint32_t batch_size);

// ============================================================================
// Configuration Management
// ============================================================================

/**
 * Load configuration from file
 * @param config_path Path to configuration file
 * @return Configuration handle or NULL on failure
 */
ZekeConfigHandle* zeke_load_config(const char* config_path);

/**
 * Save configuration to file
 * @param config_handle Configuration handle
 * @param config_path Path to save configuration
 * @return Error code
 */
ZekeErrorCode zeke_save_config(ZekeConfigHandle* config_handle, const char* config_path);

/**
 * Free configuration handle
 * @param config_handle Configuration handle to free
 */
void zeke_free_config(ZekeConfigHandle* config_handle);

// ============================================================================
// Utility Functions
// ============================================================================

/**
 * Get last error message (thread-local)
 * @return Error message string
 */
const char* zeke_get_last_error(void);

/**
 * Check if Zeke instance is healthy
 * @param handle Zeke instance handle
 * @return Error code (ZEKE_SUCCESS if healthy)
 */
ZekeErrorCode zeke_health_check(ZekeHandle* handle);

#ifdef __cplusplus
}
#endif

#endif // ZEKE_FFI_H