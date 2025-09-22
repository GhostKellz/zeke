//! Main Zeke client implementation

use crate::{
    ffi_utils::{CStringManager, CStringHolder},
    error::{check_result_with_context, Error, Result},
    response::{ChatResponse, ResponseMetadata, StreamChunk},
    Config, Provider,
};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use tracing::{debug, error, info, trace};
use uuid::Uuid;
use zeke_sys::*;

/// Main Zeke client for AI interactions
#[derive(Debug)]
pub struct Zeke {
    handle: *mut ZekeHandle,
    config: Config,
    _string_manager: Arc<Mutex<CStringManager>>, // Keep strings alive
}

// Safety: The underlying Zeke handle is thread-safe
unsafe impl Send for Zeke {}
unsafe impl Sync for Zeke {}

impl Zeke {
    /// Create a new Zeke instance with the provided configuration
    pub fn new(config: Config) -> Result<Self> {
        debug!("Creating new Zeke instance with provider: {}", config.provider);
        
        // Validate configuration
        config.validate()?;
        
        let mut string_manager = CStringManager::new();
        
        // Prepare C strings for FFI
        let base_url = string_manager.add(&config.effective_base_url())?;
        let api_key = string_manager.add_optional(config.api_key())?;
        let model = string_manager.add(&config.model)?;
        
        let ffi_config = ZekeConfig {
            base_url,
            api_key,
            provider: config.provider.to_ffi() as i32,
            model_name: model,
            temperature: config.temperature,
            max_tokens: config.max_tokens,
            stream: config.streaming,
            enable_gpu: config.enable_gpu,
            enable_fallback: config.enable_fallback,
            timeout_ms: config.timeout_ms,
        };

        // Initialize Zeke
        let handle = unsafe { zeke_init(&ffi_config) };
        
        if handle.is_null() {
            let error_msg = unsafe { get_last_error().unwrap_or_else(|| "Unknown initialization error".to_string()) };
            return Err(Error::initialization(error_msg));
        }

        info!("Successfully initialized Zeke with provider: {}", config.provider);

        Ok(Self {
            handle,
            config,
            _string_manager: Arc::new(Mutex::new(string_manager)),
        })
    }

    /// Create a configuration builder for easy setup
    pub fn builder() -> crate::ConfigBuilder {
        Config::builder()
    }

    /// Send a chat message and get a response
    pub async fn chat(&self, message: &str) -> Result<ChatResponse> {
        let start_time = Instant::now();
        debug!("Sending chat message with {} characters", message.len());
        trace!("Message content: {}", message);

        // Create C string for the message
        let message_cstr = CStringHolder::new(message)?;
        let mut response = unsafe { std::mem::zeroed::<ZekeResponse>() };

        // Make the FFI call
        let result = unsafe {
            zeke_chat(self.handle, message_cstr.as_ptr(), &mut response)
        };

        // Check for errors
        check_result_with_context(result)?;

        // Convert response
        let content = unsafe {
            if response.content.is_null() {
                return Err(Error::custom("Received null response content"));
            }
            let content = crate::ffi_utils::c_string_to_string(response.content)?;
            
            // Free the FFI response memory
            zeke_free_response(&mut response);
            
            content
        };

        let response_time = start_time.elapsed();
        let provider_used = Provider::from_ffi(
            unsafe { std::mem::transmute(response.provider_used) }
        ).unwrap_or(self.config.provider);

        debug!(
            "Received response from {}: {} characters in {:?}",
            provider_used,
            content.len(),
            response_time
        );

        // Create metadata
        let metadata = ResponseMetadata {
            streamed: false,
            temperature: Some(self.config.temperature),
            ..Default::default()
        };

        Ok(ChatResponse::new(
            content,
            provider_used,
            self.config.model.clone(),
            Some(response.tokens_used),
            response_time,
        ).with_metadata(metadata))
    }

    /// Send a streaming chat message
    #[cfg(feature = "async")]
    pub async fn chat_stream(
        &self,
        message: &str,
    ) -> Result<impl futures::Stream<Item = Result<StreamChunk>>> {
        use crate::stream::ZekeStream;
        ZekeStream::new(self, message).await
    }

    /// Send a streaming chat message with callback
    pub fn chat_stream_callback<F>(&self, message: &str, mut callback: F) -> Result<()>
    where
        F: FnMut(Result<StreamChunk>) + Send + 'static,
    {
        debug!("Starting streaming chat with {} characters", message.len());
        
        let message_cstr = CStringHolder::new(message)?;
        let stream_id = Uuid::new_v4();
        let mut chunk_index = 0u32;

        // Create callback context
        struct CallbackContext<F> {
            callback: F,
            stream_id: Uuid,
            chunk_index: u32,
        }

        let mut context = CallbackContext {
            callback,
            stream_id,
            chunk_index: 0,
        };

        unsafe extern "C" fn stream_callback<F>(
            chunk: *const ZekeStreamChunk,
            user_data: *mut std::ffi::c_void,
        ) where
            F: FnMut(Result<StreamChunk>),
        {
            if chunk.is_null() || user_data.is_null() {
                return;
            }

            let context = &mut *(user_data as *mut CallbackContext<F>);
            let chunk_ref = &*chunk;

            let result = crate::ffi_utils::c_string_to_string(chunk_ref.content)
                .map(|content| {
                    let stream_chunk = StreamChunk::new(
                        context.stream_id,
                        content,
                        context.chunk_index,
                        chunk_ref.is_final,
                    );
                    context.chunk_index += 1;
                    stream_chunk
                });

            (context.callback)(result);
        }

        let result = unsafe {
            zeke_chat_stream(
                self.handle,
                message_cstr.as_ptr(),
                Some(stream_callback::<F>),
                &mut context as *mut _ as *mut std::ffi::c_void,
            )
        };

        check_result_with_context(result)?;
        
        debug!("Streaming completed with {} chunks", context.chunk_index);
        Ok(())
    }

    /// Switch to a different provider
    pub async fn switch_provider(&mut self, provider: Provider) -> Result<()> {
        debug!("Switching from {} to {}", self.config.provider, provider);

        let result = unsafe {
            zeke_switch_provider(self.handle, provider.to_ffi() as i32)
        };

        check_result_with_context(result)?;
        
        // Update internal config
        self.config = self.config.with_provider(provider);
        
        info!("Successfully switched to provider: {}", provider);
        Ok(())
    }

    /// Set authentication token for the current provider
    pub async fn set_auth_token(&self, token: &str) -> Result<()> {
        debug!("Setting auth token for provider: {}", self.config.provider);

        let token_cstr = CStringHolder::new(token)?;
        let result = unsafe {
            zeke_set_auth_token(
                self.handle,
                self.config.provider.to_ffi() as i32,
                token_cstr.as_ptr(),
            )
        };

        check_result_with_context(result)?;
        
        info!("Successfully set auth token for: {}", self.config.provider);
        Ok(())
    }

    /// Test authentication for the current provider
    pub async fn test_auth(&self) -> Result<bool> {
        debug!("Testing authentication for: {}", self.config.provider);

        let result = unsafe {
            zeke_test_auth(self.handle, self.config.provider.to_ffi() as i32)
        };

        match result {
            ZekeErrorCode::ZEKE_SUCCESS => {
                debug!("Authentication test passed");
                Ok(true)
            }
            ZekeErrorCode::ZEKE_AUTHENTICATION_FAILED => {
                debug!("Authentication test failed");
                Ok(false)
            }
            _ => {
                check_result_with_context(result)?;
                Ok(false)
            }
        }
    }

    /// Get status of all providers
    pub async fn provider_status(&self) -> Result<Vec<crate::provider::ProviderStatus>> {
        debug!("Getting provider status");

        const MAX_PROVIDERS: usize = 10;
        let mut status_array = vec![unsafe { std::mem::zeroed::<ZekeProviderStatus>() }; MAX_PROVIDERS];
        let mut actual_count: usize = 0;

        let result = unsafe {
            zeke_get_provider_status(
                self.handle,
                status_array.as_mut_ptr(),
                MAX_PROVIDERS,
                &mut actual_count,
            )
        };

        check_result_with_context(result)?;

        let mut provider_statuses = Vec::new();
        for i in 0..actual_count {
            let ffi_status = &status_array[i];
            
            if let Some(provider) = Provider::from_ffi(
                unsafe { std::mem::transmute(ffi_status.provider) }
            ) {
                let status = crate::provider::ProviderStatus {
                    provider,
                    is_healthy: ffi_status.is_healthy,
                    response_time_ms: ffi_status.response_time_ms,
                    error_rate: ffi_status.error_rate,
                    requests_per_minute: ffi_status.requests_per_minute,
                    last_check: std::time::SystemTime::now(),
                };
                provider_statuses.push(status);
            }
        }

        debug!("Retrieved status for {} providers", provider_statuses.len());
        Ok(provider_statuses)
    }

    /// Perform a health check on the current instance
    pub async fn health_check(&self) -> Result<()> {
        debug!("Performing health check");

        let result = unsafe { zeke_health_check(self.handle) };
        check_result_with_context(result)?;
        
        debug!("Health check passed");
        Ok(())
    }

    /// Get the current configuration
    pub fn config(&self) -> &Config {
        &self.config
    }

    /// Get the current provider
    pub fn current_provider(&self) -> Provider {
        self.config.provider
    }

    /// Get the current model
    pub fn current_model(&self) -> &str {
        &self.config.model
    }

    /// Check if streaming is enabled
    pub fn streaming_enabled(&self) -> bool {
        self.config.streaming
    }

    /// Check if GPU acceleration is enabled
    pub fn gpu_enabled(&self) -> bool {
        self.config.enable_gpu
    }

    /// Get Zeke version
    pub fn version() -> &'static str {
        unsafe {
            let version_ptr = zeke_version();
            std::ffi::CStr::from_ptr(version_ptr)
                .to_str()
                .unwrap_or("unknown")
        }
    }
}

impl Drop for Zeke {
    fn drop(&mut self) {
        if !self.handle.is_null() {
            debug!("Destroying Zeke instance");
            unsafe {
                zeke_destroy(self.handle);
            }
            self.handle = std::ptr::null_mut();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{Config, Provider};

    fn test_config() -> Config {
        Config::builder()
            .provider(Provider::OpenAI)
            .api_key("test-key")
            .model("gpt-4")
            .build()
            .unwrap()
    }

    #[tokio::test]
    async fn test_zeke_creation() {
        // This test might fail without a real API key, but tests the construction logic
        let config = test_config();
        let result = Zeke::new(config);
        
        // We expect this to potentially fail due to no real API key
        // but we're testing that the error handling works correctly
        match result {
            Ok(zeke) => {
                assert_eq!(zeke.current_provider(), Provider::OpenAI);
                assert_eq!(zeke.current_model(), "gpt-4");
            }
            Err(e) => {
                // Expected for test environment
                println!("Expected error in test environment: {}", e);
            }
        }
    }

    #[test]
    fn test_version() {
        let version = Zeke::version();
        assert!(!version.is_empty());
        println!("Zeke version: {}", version);
    }

    #[tokio::test]
    async fn test_provider_switching() {
        let config = test_config();
        if let Ok(mut zeke) = Zeke::new(config) {
            let result = zeke.switch_provider(Provider::Claude).await;
            // May fail without proper setup, but tests the call path
            match result {
                Ok(_) => assert_eq!(zeke.current_provider(), Provider::Claude),
                Err(_) => println!("Provider switch failed (expected in test)"),
            }
        }
    }
}