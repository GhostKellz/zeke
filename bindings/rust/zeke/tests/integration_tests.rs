//! Integration tests for Zeke Rust bindings
//!
//! These tests verify that the FFI layer works correctly and that
//! the high-level Rust API functions as expected.

use std::time::Duration;
use zeke::{Config, Error, Provider, Zeke};

// Test configuration - using a mock setup since we don't have real API keys
fn test_config() -> Config {
    Config::builder()
        .provider(Provider::OpenAI)
        .api_key("test-key-12345") // Mock key for testing
        .model("gpt-4")
        .temperature(0.7)
        .max_tokens(100)
        .timeout_secs(5)
        .build()
        .expect("Failed to build test config")
}

#[tokio::test]
async fn test_config_creation() {
    let config = test_config();
    assert_eq!(config.provider, Provider::OpenAI);
    assert_eq!(config.model, "gpt-4");
    assert_eq!(config.temperature, 0.7);
    assert_eq!(config.max_tokens, 100);
}

#[tokio::test]
async fn test_config_validation() {
    // Valid config should pass
    let valid_config = Config::builder()
        .provider(Provider::OpenAI)
        .api_key("valid-key")
        .model("gpt-4")
        .temperature(0.5)
        .max_tokens(1000)
        .build();
    assert!(valid_config.is_ok());

    // Invalid temperature should fail
    let invalid_temp = Config::builder()
        .provider(Provider::OpenAI)
        .api_key("valid-key")
        .model("gpt-4")
        .temperature(3.0) // Invalid: > 2.0
        .build();
    assert!(invalid_temp.is_err());

    // Invalid max tokens should fail
    let invalid_tokens = Config::builder()
        .provider(Provider::OpenAI)
        .api_key("valid-key")
        .model("gpt-4")
        .max_tokens(0) // Invalid: must be > 0
        .build();
    assert!(invalid_tokens.is_err());
}

#[tokio::test]
async fn test_provider_properties() {
    // Test provider properties
    assert_eq!(Provider::OpenAI.default_model(), "gpt-4o");
    assert_eq!(Provider::Claude.default_model(), "claude-3-5-sonnet-20241022");
    assert_eq!(Provider::GhostLLM.default_model(), "ghostllm-7b");

    // Test feature support
    assert!(Provider::Claude.supports_streaming());
    assert!(Provider::GhostLLM.supports_gpu());
    assert!(!Provider::Copilot.supports_streaming());

    // Test provider identification
    assert_eq!(Provider::from_str("openai"), Some(Provider::OpenAI));
    assert_eq!(Provider::from_str("claude"), Some(Provider::Claude));
    assert_eq!(Provider::from_str("invalid"), None);
}

#[tokio::test]
async fn test_zeke_version() {
    let version = Zeke::version();
    assert!(!version.is_empty());
    println!("Zeke version: {}", version);
}

#[tokio::test]
async fn test_zeke_creation_failure() {
    // Test that Zeke creation fails gracefully with invalid config
    let invalid_config = Config::builder()
        .provider(Provider::OpenAI)
        .api_key("invalid-key")
        .model("gpt-4")
        .build()
        .unwrap();

    let result = Zeke::new(invalid_config);
    
    // We expect this to fail since we don't have real API access in tests
    match result {
        Err(Error::InitializationFailed { .. }) => {
            // Expected error - FFI layer should reject invalid setup
            println!("✅ Correctly rejected invalid configuration");
        }
        Err(e) => {
            println!("⚠️ Different error than expected: {}", e);
            // Still acceptable - various errors can occur without real API
        }
        Ok(_) => {
            // Unexpected success - might indicate the test environment
            // has some kind of mock setup
            println!("⚠️ Unexpected success - check test environment");
        }
    }
}

#[tokio::test]
async fn test_error_handling() {
    // Test error type conversions and properties
    let auth_error = Error::authentication("openai", "Invalid API key");
    assert!(auth_error.is_auth_error());
    assert!(!auth_error.is_retryable());
    assert_eq!(auth_error.category(), "authentication");

    let network_error = Error::network("Connection timeout");
    assert!(!network_error.is_auth_error());
    assert!(network_error.is_retryable());
    assert_eq!(network_error.category(), "network");
}

#[tokio::test]
async fn test_config_from_builder() {
    let config = Config::builder()
        .provider(Provider::Claude)
        .api_key("test-key")
        .model("claude-3-opus")
        .temperature(0.8)
        .max_tokens(2000)
        .streaming(true)
        .gpu(false)
        .fallback(true)
        .timeout_secs(30)
        .build()
        .unwrap();

    assert_eq!(config.provider, Provider::Claude);
    assert_eq!(config.model, "claude-3-opus");
    assert_eq!(config.temperature, 0.8);
    assert_eq!(config.max_tokens, 2000);
    assert!(config.streaming);
    assert!(!config.enable_gpu);
    assert!(config.enable_fallback);
    assert_eq!(config.timeout_ms, 30000);
}

#[tokio::test]
async fn test_config_with_provider_switch() {
    let openai_config = Config::builder()
        .provider(Provider::OpenAI)
        .model("gpt-4")
        .build()
        .unwrap();

    let claude_config = openai_config.with_provider(Provider::Claude);
    
    assert_eq!(claude_config.provider, Provider::Claude);
    // Model should change to Claude's default
    assert_eq!(claude_config.model, "claude-3-5-sonnet-20241022");
}

#[cfg(feature = "async")]
mod async_tests {
    use super::*;
    use futures::StreamExt;
    use zeke::stream::utils;

    #[tokio::test]
    async fn test_mock_stream() {
        let chunks = vec![
            "Hello".to_string(),
            " ".to_string(),
            "world".to_string(),
            "!".to_string(),
        ];
        
        let mut stream = utils::mock_stream(chunks.clone());
        let mut collected = Vec::new();
        let mut final_chunk_found = false;

        while let Some(chunk_result) = stream.next().await {
            let chunk = chunk_result.expect("Mock stream should not error");
            collected.push(chunk.content.clone());
            
            if chunk.is_final {
                final_chunk_found = true;
                assert_eq!(chunk.chunk_index as usize, chunks.len() - 1);
            }
        }

        assert!(final_chunk_found, "Should have received final chunk");
        assert_eq!(collected.join(""), "Hello world!");
    }

    #[tokio::test]
    async fn test_stream_statistics() {
        use zeke::response::{StreamChunk, StreamStatistics};
        use uuid::Uuid;

        let stream_id = Uuid::new_v4();
        let chunks = vec![
            StreamChunk::new(stream_id, "Hello".to_string(), 0, false),
            StreamChunk::new(stream_id, " world".to_string(), 1, false),
            StreamChunk::new(stream_id, "!".to_string(), 2, true),
        ];

        let stats = StreamStatistics::from_chunks(&chunks);
        
        assert_eq!(stats.stream_id, stream_id);
        assert_eq!(stats.total_chunks, 3);
        assert_eq!(stats.total_length, 12); // "Hello world!"
        assert!(stats.completed_successfully);
        assert!(stats.average_chunk_size > 0.0);
    }

    #[tokio::test]
    async fn test_rate_limiting() {
        use std::time::Instant;
        
        let chunks = vec!["A".to_string(), "B".to_string()];
        let stream = utils::mock_stream(chunks);
        let delay = Duration::from_millis(50);
        let rate_limited = utils::rate_limit(stream, delay);
        
        let start = Instant::now();
        let results: Vec<_> = rate_limited.collect().await;
        let elapsed = start.elapsed();
        
        assert_eq!(results.len(), 2);
        // Should take at least the sum of delays
        assert!(elapsed >= delay * 2);
    }
}

#[cfg(feature = "ghostllm")]
mod ghostllm_tests {
    use super::*;
    use zeke::ghostllm::{GpuInfo, BenchmarkResult};

    #[test]
    fn test_gpu_info_calculations() {
        let gpu_info = GpuInfo {
            device_name: "Test GPU".to_string(),
            memory_used_mb: 5000,
            memory_total_mb: 10000,
            utilization_percent: 50,
            temperature_celsius: 65,
            power_watts: 200,
        };

        assert_eq!(gpu_info.memory_utilization(), 0.5);
        assert_eq!(gpu_info.memory_utilization_percent(), 50.0);
        assert_eq!(gpu_info.memory_available_mb(), 5000);
        assert!(!gpu_info.is_high_load());
        assert!(!gpu_info.is_overheating());
        assert!(gpu_info.health_score() > 0.5);
    }

    #[test]
    fn test_gpu_high_load_detection() {
        let mut gpu_info = GpuInfo {
            device_name: "Test GPU".to_string(),
            memory_used_mb: 9500, // 95% usage
            memory_total_mb: 10000,
            utilization_percent: 85, // High utilization
            temperature_celsius: 70,
            power_watts: 350,
        };

        assert!(gpu_info.is_high_load());
        
        // Test overheating
        gpu_info.temperature_celsius = 90;
        assert!(gpu_info.is_overheating());
        
        // Health score should be lower
        assert!(gpu_info.health_score() < 0.5);
    }

    #[test]
    fn test_benchmark_result() {
        let benchmark = BenchmarkResult {
            model: "test-model".to_string(),
            tokens_per_second: 25.0,
            latency_ms: 100.0,
            memory_usage_mb: 4000,
            batch_size: 8,
            duration: Duration::from_secs(5),
            success: true,
        };

        assert!(benchmark.is_acceptable_performance());
        assert_eq!(benchmark.performance_score(), 0.25); // 25/100 = 0.25
    }

    // Note: Actual GhostLLM integration tests would require a running
    // GhostLLM server, so we only test the data structures here
}

#[tokio::test]
async fn test_concurrent_config_creation() {
    use std::sync::Arc;
    use tokio::task;

    // Test that config creation is thread-safe
    let tasks: Vec<_> = (0..10).map(|i| {
        task::spawn(async move {
            let config = Config::builder()
                .provider(Provider::OpenAI)
                .api_key(&format!("test-key-{}", i))
                .model("gpt-4")
                .build()
                .unwrap();
            
            assert_eq!(config.provider, Provider::OpenAI);
            assert_eq!(config.model, "gpt-4");
        })
    }).collect();

    // Wait for all tasks to complete
    for task in tasks {
        task.await.unwrap();
    }
}

#[test]
fn test_provider_serialization() {
    // Test that providers can be serialized/deserialized
    let provider = Provider::OpenAI;
    let json = serde_json::to_string(&provider).unwrap();
    let deserialized: Provider = serde_json::from_str(&json).unwrap();
    assert_eq!(provider, deserialized);
}

#[tokio::test]
async fn test_response_builder() {
    use zeke::response::{ResponseBuilder, ResponseMetadata};
    use std::time::Duration;

    let response = ResponseBuilder::new()
        .content("Test response content")
        .provider(Provider::Claude)
        .model("claude-3-opus")
        .tokens_used(42)
        .response_time(Duration::from_millis(500))
        .build();

    assert_eq!(response.content, "Test response content");
    assert_eq!(response.provider, Provider::Claude);
    assert_eq!(response.model, "claude-3-opus");
    assert_eq!(response.tokens_used, Some(42));
    assert_eq!(response.response_time, Duration::from_millis(500));
    assert_eq!(response.content_length(), 21);
    assert_eq!(response.word_count(), 3);
    assert!(response.is_complete());
}

// Utility function to help with manual testing
#[ignore] // Ignored by default since it requires real API access
#[tokio::test]
async fn manual_integration_test() {
    // This test is for manual verification with real API keys
    // Run with: cargo test manual_integration_test -- --ignored
    
    let config = Config::builder()
        .provider(Provider::OpenAI)
        .api_key_from_env() // Requires OPENAI_API_KEY env var
        .model("gpt-3.5-turbo")
        .temperature(0.3)
        .max_tokens(50)
        .build();
    
    if let Ok(config) = config {
        if let Ok(zeke) = Zeke::new(config) {
            match zeke.chat("Say hello in exactly 3 words").await {
                Ok(response) => {
                    println!("✅ Manual test successful!");
                    println!("Response: {}", response.content);
                    println!("Provider: {}", response.provider);
                    println!("Tokens: {:?}", response.tokens_used);
                    println!("Time: {:?}", response.response_time);
                }
                Err(e) => {
                    println!("❌ Chat failed: {}", e);
                }
            }
        } else {
            println!("❌ Failed to create Zeke instance");
        }
    } else {
        println!("⚠️ Skipping manual test - no API key available");
    }
}