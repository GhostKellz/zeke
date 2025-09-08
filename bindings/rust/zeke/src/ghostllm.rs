//! GhostLLM GPU acceleration features

use crate::{
    error::{check_result_with_context, Error, Result},
    ffi_utils::CStringHolder,
    Zeke,
};
use serde::{Deserialize, Serialize};
use std::time::Duration;
use tracing::{debug, info, warn};
use zeke_sys::*;

/// GPU information from GhostLLM
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GpuInfo {
    /// GPU device name
    pub device_name: String,
    /// Memory used in MB
    pub memory_used_mb: u64,
    /// Total memory in MB
    pub memory_total_mb: u64,
    /// GPU utilization percentage (0-100)
    pub utilization_percent: u8,
    /// GPU temperature in Celsius
    pub temperature_celsius: u8,
    /// Power consumption in Watts
    pub power_watts: u32,
}

impl GpuInfo {
    /// Get memory utilization as a percentage (0.0 to 1.0)
    pub fn memory_utilization(&self) -> f64 {
        if self.memory_total_mb == 0 {
            0.0
        } else {
            self.memory_used_mb as f64 / self.memory_total_mb as f64
        }
    }

    /// Get memory utilization as a percentage (0-100)
    pub fn memory_utilization_percent(&self) -> f64 {
        self.memory_utilization() * 100.0
    }

    /// Get available memory in MB
    pub fn memory_available_mb(&self) -> u64 {
        self.memory_total_mb.saturating_sub(self.memory_used_mb)
    }

    /// Check if GPU is under high load
    pub fn is_high_load(&self) -> bool {
        self.utilization_percent > 80 || self.memory_utilization() > 0.9
    }

    /// Check if GPU is overheating
    pub fn is_overheating(&self) -> bool {
        self.temperature_celsius > 85 // Common threshold for GPU thermal throttling
    }

    /// Get a health score from 0.0 to 1.0
    pub fn health_score(&self) -> f64 {
        let mut score = 1.0;

        // Penalize high utilization
        if self.utilization_percent > 90 {
            score -= 0.3;
        } else if self.utilization_percent > 80 {
            score -= 0.1;
        }

        // Penalize high memory usage
        if self.memory_utilization() > 0.95 {
            score -= 0.3;
        } else if self.memory_utilization() > 0.85 {
            score -= 0.1;
        }

        // Penalize high temperature
        if self.temperature_celsius > 85 {
            score -= 0.4;
        } else if self.temperature_celsius > 75 {
            score -= 0.2;
        }

        score.max(0.0)
    }
}

/// Benchmark results from GhostLLM
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BenchmarkResult {
    /// Model that was benchmarked
    pub model: String,
    /// Tokens per second
    pub tokens_per_second: f64,
    /// Average latency in milliseconds
    pub latency_ms: f64,
    /// Memory usage during benchmark
    pub memory_usage_mb: u64,
    /// Batch size used
    pub batch_size: u32,
    /// Duration of the benchmark
    pub duration: Duration,
    /// Whether the benchmark completed successfully
    pub success: bool,
}

impl BenchmarkResult {
    /// Get performance score (0.0 to 1.0 based on tokens per second)
    pub fn performance_score(&self) -> f64 {
        // Rough scoring based on typical LLM performance
        // This is model-dependent and should be calibrated
        let baseline_tps = 10.0; // Baseline tokens per second
        let max_tps = 100.0; // High-end performance
        
        (self.tokens_per_second / max_tps).min(1.0).max(0.0)
    }

    /// Check if performance is acceptable
    pub fn is_acceptable_performance(&self) -> bool {
        self.success && self.tokens_per_second > 1.0 && self.latency_ms < 10000.0
    }
}

/// GhostLLM GPU acceleration interface
pub struct GhostLLM<'a> {
    zeke: &'a Zeke,
    initialized: bool,
}

impl<'a> GhostLLM<'a> {
    /// Create a new GhostLLM instance
    pub(crate) fn new(zeke: &'a Zeke) -> Self {
        Self {
            zeke,
            initialized: false,
        }
    }

    /// Initialize GhostLLM with default settings
    pub async fn initialize(&mut self) -> Result<()> {
        self.initialize_with_url("http://localhost:8080", true).await
    }

    /// Initialize GhostLLM with custom settings
    pub async fn initialize_with_url(&mut self, base_url: &str, enable_gpu: bool) -> Result<()> {
        debug!("Initializing GhostLLM with URL: {}, GPU: {}", base_url, enable_gpu);

        let url_cstr = CStringHolder::new(base_url)?;
        let result = unsafe {
            zeke_ghostllm_init(self.zeke.handle, url_cstr.as_ptr(), enable_gpu)
        };

        check_result_with_context(result)?;
        self.initialized = true;

        info!("GhostLLM initialized successfully");
        Ok(())
    }

    /// Get GPU information
    pub async fn gpu_info(&self) -> Result<GpuInfo> {
        if !self.initialized {
            return Err(Error::custom("GhostLLM not initialized"));
        }

        debug!("Getting GPU information");

        let mut gpu_info = unsafe { std::mem::zeroed::<ZekeGpuInfo>() };
        let result = unsafe {
            zeke_ghostllm_get_gpu_info(self.zeke.handle, &mut gpu_info)
        };

        check_result_with_context(result)?;

        let device_name = unsafe {
            crate::ffi_utils::c_string_to_string(gpu_info.device_name)?
        };

        let info = GpuInfo {
            device_name,
            memory_used_mb: gpu_info.memory_used_mb,
            memory_total_mb: gpu_info.memory_total_mb,
            utilization_percent: gpu_info.utilization_percent,
            temperature_celsius: gpu_info.temperature_celsius,
            power_watts: gpu_info.power_watts,
        };

        // Free the FFI memory
        unsafe {
            zeke_free_gpu_info(&mut gpu_info);
        }

        debug!("Retrieved GPU info: {:.1}% utilization, {}°C", 
               info.utilization_percent, info.temperature_celsius);

        Ok(info)
    }

    /// Run a benchmark on the specified model
    pub async fn benchmark(&self, model: &str, batch_size: u32) -> Result<BenchmarkResult> {
        if !self.initialized {
            return Err(Error::custom("GhostLLM not initialized"));
        }

        info!("Starting benchmark for model: {} with batch size: {}", model, batch_size);

        let model_cstr = CStringHolder::new(model)?;
        let start_time = std::time::Instant::now();

        let result = unsafe {
            zeke_ghostllm_benchmark(self.zeke.handle, model_cstr.as_ptr(), batch_size)
        };

        let duration = start_time.elapsed();
        let success = result == ZekeErrorCode::ZEKE_SUCCESS;

        if !success {
            warn!("Benchmark failed for model: {}", model);
        }

        // For now, we return basic benchmark results
        // In a real implementation, the FFI would return detailed metrics
        let benchmark_result = BenchmarkResult {
            model: model.to_string(),
            tokens_per_second: if success { 25.0 } else { 0.0 }, // Placeholder
            latency_ms: duration.as_millis() as f64,
            memory_usage_mb: 0, // Would get from actual benchmark
            batch_size,
            duration,
            success,
        };

        if success {
            info!("Benchmark completed: {:.2} tokens/second, {:.2}ms latency", 
                  benchmark_result.tokens_per_second, 
                  benchmark_result.latency_ms);
        }

        Ok(benchmark_result)
    }

    /// Check if GhostLLM is available and healthy
    pub async fn health_check(&self) -> Result<bool> {
        if !self.initialized {
            return Ok(false);
        }

        match self.gpu_info().await {
            Ok(info) => {
                let health_score = info.health_score();
                let is_healthy = health_score > 0.5 && !info.is_overheating();
                
                debug!("GhostLLM health check: score={:.2}, healthy={}", 
                       health_score, is_healthy);
                
                Ok(is_healthy)
            }
            Err(_) => Ok(false),
        }
    }

    /// Get memory utilization percentage
    pub async fn memory_utilization(&self) -> Result<f64> {
        let info = self.gpu_info().await?;
        Ok(info.memory_utilization_percent())
    }

    /// Wait for GPU to be available (low utilization)
    pub async fn wait_for_availability(&self, timeout: Duration) -> Result<()> {
        let start_time = std::time::Instant::now();
        let check_interval = Duration::from_millis(500);

        while start_time.elapsed() < timeout {
            match self.gpu_info().await {
                Ok(info) => {
                    if !info.is_high_load() && !info.is_overheating() {
                        debug!("GPU is available");
                        return Ok(());
                    }
                    debug!("GPU still busy: {}% utilization, {}°C", 
                           info.utilization_percent, info.temperature_celsius);
                }
                Err(e) => {
                    warn!("Failed to get GPU info while waiting: {}", e);
                }
            }

            tokio::time::sleep(check_interval).await;
        }

        Err(Error::custom("Timeout waiting for GPU availability"))
    }

    /// Get optimal batch size based on current GPU memory
    pub async fn optimal_batch_size(&self) -> Result<u32> {
        let info = self.gpu_info().await?;
        let available_memory_gb = info.memory_available_mb() as f64 / 1024.0;
        
        // Rough heuristic: 1GB per 4 batch items for typical models
        let optimal_batch = ((available_memory_gb * 4.0) as u32).max(1).min(64);
        
        debug!("Recommended batch size: {} (based on {:.1}GB available memory)", 
               optimal_batch, available_memory_gb);
        
        Ok(optimal_batch)
    }

    /// Check if GhostLLM is initialized
    pub fn is_initialized(&self) -> bool {
        self.initialized
    }
}

/// Convenience functions for GhostLLM integration
impl Zeke {
    /// Get GhostLLM interface
    #[cfg(feature = "ghostllm")]
    pub fn ghostllm(&self) -> GhostLLM<'_> {
        GhostLLM::new(self)
    }

    /// Quick GPU info check
    #[cfg(feature = "ghostllm")]
    pub async fn gpu_info(&self) -> Result<GpuInfo> {
        let mut ghostllm = self.ghostllm();
        if !ghostllm.is_initialized() {
            ghostllm.initialize().await?;
        }
        ghostllm.gpu_info().await
    }

    /// Quick benchmark
    #[cfg(feature = "ghostllm")]
    pub async fn benchmark_model(&self, model: &str) -> Result<BenchmarkResult> {
        let mut ghostllm = self.ghostllm();
        if !ghostllm.is_initialized() {
            ghostllm.initialize().await?;
        }
        
        let batch_size = ghostllm.optimal_batch_size().await.unwrap_or(8);
        ghostllm.benchmark(model, batch_size).await
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_gpu_info() -> GpuInfo {
        GpuInfo {
            device_name: "NVIDIA RTX 4090".to_string(),
            memory_used_mb: 12000,
            memory_total_mb: 24000,
            utilization_percent: 75,
            temperature_celsius: 65,
            power_watts: 350,
        }
    }

    #[test]
    fn test_gpu_info_calculations() {
        let info = sample_gpu_info();
        
        assert_eq!(info.memory_utilization(), 0.5);
        assert_eq!(info.memory_utilization_percent(), 50.0);
        assert_eq!(info.memory_available_mb(), 12000);
        assert!(!info.is_high_load());
        assert!(!info.is_overheating());
        assert!(info.health_score() > 0.7);
    }

    #[test]
    fn test_gpu_high_load_detection() {
        let mut info = sample_gpu_info();
        info.utilization_percent = 85;
        info.memory_used_mb = 22000; // ~92% memory usage
        
        assert!(info.is_high_load());
        assert!(info.health_score() < 0.5);
    }

    #[test]
    fn test_gpu_overheating_detection() {
        let mut info = sample_gpu_info();
        info.temperature_celsius = 90;
        
        assert!(info.is_overheating());
        assert!(info.health_score() < 0.6);
    }

    #[test]
    fn test_benchmark_performance_scoring() {
        let benchmark = BenchmarkResult {
            model: "test-model".to_string(),
            tokens_per_second: 50.0,
            latency_ms: 200.0,
            memory_usage_mb: 8000,
            batch_size: 16,
            duration: Duration::from_secs(10),
            success: true,
        };
        
        assert_eq!(benchmark.performance_score(), 0.5); // 50/100 = 0.5
        assert!(benchmark.is_acceptable_performance());
    }
}