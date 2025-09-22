//! Response types for AI interactions

use crate::Provider;
use serde::{Deserialize, Serialize};
use std::time::{Duration, SystemTime};
use uuid::Uuid;

/// Response from a chat interaction
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatResponse {
    /// Unique identifier for this response
    pub id: Uuid,
    
    /// The response content
    pub content: String,
    
    /// Provider that generated the response
    pub provider: Provider,
    
    /// Model used for generation
    pub model: String,
    
    /// Number of tokens used in the request
    pub tokens_used: Option<u32>,
    
    /// Time taken to generate the response
    pub response_time: Duration,
    
    /// Timestamp when the response was created
    pub created_at: SystemTime,
    
    /// Additional metadata from the provider
    pub metadata: ResponseMetadata,
}

impl ChatResponse {
    /// Create a new chat response
    pub(crate) fn new(
        content: String,
        provider: Provider,
        model: String,
        tokens_used: Option<u32>,
        response_time: Duration,
    ) -> Self {
        Self {
            id: Uuid::new_v4(),
            content,
            provider,
            model,
            tokens_used,
            response_time,
            created_at: SystemTime::now(),
            metadata: ResponseMetadata::default(),
        }
    }

    /// Get the response length in characters
    pub fn content_length(&self) -> usize {
        self.content.len()
    }

    /// Get the response length in words (approximate)
    pub fn word_count(&self) -> usize {
        self.content.split_whitespace().count()
    }

    /// Check if the response appears to be complete
    pub fn is_complete(&self) -> bool {
        // Basic heuristics for completion
        let content = self.content.trim();
        
        // Empty responses are incomplete
        if content.is_empty() {
            return false;
        }
        
        // Responses ending with common incomplete indicators
        let incomplete_endings = [
            "...",
            "…",
            "[continued]",
            "[truncated]",
            "More content needed",
        ];
        
        !incomplete_endings.iter().any(|ending| content.ends_with(ending))
    }

    /// Get the cost estimate for this response (if available)
    pub fn estimated_cost(&self) -> Option<f64> {
        self.metadata.cost_estimate
    }

    /// Set metadata
    pub(crate) fn with_metadata(mut self, metadata: ResponseMetadata) -> Self {
        self.metadata = metadata;
        self
    }
}

/// Metadata associated with a response
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ResponseMetadata {
    /// Estimated cost for this request (in USD)
    pub cost_estimate: Option<f64>,
    
    /// Input tokens count
    pub input_tokens: Option<u32>,
    
    /// Output tokens count
    pub output_tokens: Option<u32>,
    
    /// Model temperature used
    pub temperature: Option<f32>,
    
    /// Whether the response was streamed
    pub streamed: bool,
    
    /// Provider-specific metadata
    pub provider_data: std::collections::HashMap<String, serde_json::Value>,
    
    /// Rate limit information
    pub rate_limit_info: Option<RateLimitInfo>,
    
    /// Quality metrics
    pub quality_metrics: Option<QualityMetrics>,
}

/// Rate limiting information from the provider
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RateLimitInfo {
    /// Requests remaining in the current window
    pub requests_remaining: Option<u32>,
    
    /// Tokens remaining in the current window
    pub tokens_remaining: Option<u32>,
    
    /// When the rate limit resets
    pub reset_time: Option<SystemTime>,
    
    /// Rate limit window duration
    pub window_duration: Option<Duration>,
}

/// Quality metrics for the response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QualityMetrics {
    /// Confidence score (0.0 to 1.0)
    pub confidence: Option<f32>,
    
    /// Relevance score (0.0 to 1.0)
    pub relevance: Option<f32>,
    
    /// Safety score (0.0 to 1.0)
    pub safety: Option<f32>,
    
    /// Coherence score (0.0 to 1.0)
    pub coherence: Option<f32>,
    
    /// Overall quality score (0.0 to 1.0)
    pub overall: Option<f32>,
}

/// A chunk in a streaming response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StreamChunk {
    /// Unique identifier for the stream this chunk belongs to
    pub stream_id: Uuid,
    
    /// Content of this chunk
    pub content: String,
    
    /// Index of this chunk in the stream
    pub chunk_index: u32,
    
    /// Whether this is the final chunk
    pub is_final: bool,
    
    /// Timestamp when this chunk was created
    pub created_at: SystemTime,
    
    /// Chunk-specific metadata
    pub metadata: ChunkMetadata,
}

impl StreamChunk {
    /// Create a new stream chunk
    pub(crate) fn new(
        stream_id: Uuid,
        content: String,
        chunk_index: u32,
        is_final: bool,
    ) -> Self {
        Self {
            stream_id,
            content,
            chunk_index,
            is_final,
            created_at: SystemTime::now(),
            metadata: ChunkMetadata::default(),
        }
    }

    /// Get the chunk size in bytes
    pub fn size(&self) -> usize {
        self.content.len()
    }

    /// Check if this chunk is empty
    pub fn is_empty(&self) -> bool {
        self.content.is_empty()
    }

    /// Set metadata
    pub(crate) fn with_metadata(mut self, metadata: ChunkMetadata) -> Self {
        self.metadata = metadata;
        self
    }
}

/// Metadata for individual stream chunks
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ChunkMetadata {
    /// Token count for this chunk
    pub tokens: Option<u32>,
    
    /// Processing latency for this chunk
    pub latency: Option<Duration>,
    
    /// Quality score for this chunk
    pub quality_score: Option<f32>,
    
    /// Whether this chunk contains sensitive content
    pub contains_sensitive_content: bool,
    
    /// Provider-specific chunk data
    pub provider_data: std::collections::HashMap<String, serde_json::Value>,
}

/// Aggregated statistics for a streaming session
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StreamStatistics {
    /// Stream identifier
    pub stream_id: Uuid,
    
    /// Total number of chunks received
    pub total_chunks: u32,
    
    /// Total content length
    pub total_length: usize,
    
    /// Total tokens (if available)
    pub total_tokens: Option<u32>,
    
    /// Average chunk size
    pub average_chunk_size: f64,
    
    /// Total streaming duration
    pub total_duration: Duration,
    
    /// Average time between chunks
    pub average_chunk_interval: Duration,
    
    /// Streaming throughput (characters per second)
    pub throughput_cps: f64,
    
    /// Whether the stream completed successfully
    pub completed_successfully: bool,
    
    /// Number of chunks that contained errors
    pub error_chunks: u32,
}

impl StreamStatistics {
    /// Create statistics from a collection of chunks
    pub fn from_chunks(chunks: &[StreamChunk]) -> Self {
        if chunks.is_empty() {
            return Self::default();
        }

        let stream_id = chunks[0].stream_id;
        let total_chunks = chunks.len() as u32;
        let total_length: usize = chunks.iter().map(|c| c.content.len()).sum();
        let total_tokens: Option<u32> = chunks.iter()
            .filter_map(|c| c.metadata.tokens)
            .sum::<u32>()
            .into();

        let average_chunk_size = if total_chunks > 0 {
            total_length as f64 / total_chunks as f64
        } else {
            0.0
        };

        // Calculate duration from first to last chunk
        let start_time = chunks.first().unwrap().created_at;
        let end_time = chunks.last().unwrap().created_at;
        let total_duration = end_time.duration_since(start_time)
            .unwrap_or(Duration::from_secs(0));

        let average_chunk_interval = if total_chunks > 1 {
            total_duration / (total_chunks - 1)
        } else {
            Duration::from_secs(0)
        };

        let throughput_cps = if total_duration.as_secs_f64() > 0.0 {
            total_length as f64 / total_duration.as_secs_f64()
        } else {
            0.0
        };

        let completed_successfully = chunks.last()
            .map(|c| c.is_final)
            .unwrap_or(false);

        Self {
            stream_id,
            total_chunks,
            total_length,
            total_tokens,
            average_chunk_size,
            total_duration,
            average_chunk_interval,
            throughput_cps,
            completed_successfully,
            error_chunks: 0, // Would need error tracking to calculate this
        }
    }
}

impl Default for StreamStatistics {
    fn default() -> Self {
        Self {
            stream_id: Uuid::new_v4(),
            total_chunks: 0,
            total_length: 0,
            total_tokens: None,
            average_chunk_size: 0.0,
            total_duration: Duration::from_secs(0),
            average_chunk_interval: Duration::from_secs(0),
            throughput_cps: 0.0,
            completed_successfully: false,
            error_chunks: 0,
        }
    }
}

/// Builder for creating custom responses (useful for testing)
#[derive(Debug)]
pub struct ResponseBuilder {
    content: String,
    provider: Provider,
    model: String,
    tokens_used: Option<u32>,
    response_time: Duration,
    metadata: ResponseMetadata,
}

impl ResponseBuilder {
    /// Create a new response builder
    pub fn new() -> Self {
        Self {
            content: String::new(),
            provider: Provider::OpenAI,
            model: "gpt-4o".to_string(),
            tokens_used: None,
            response_time: Duration::from_millis(500),
            metadata: ResponseMetadata::default(),
        }
    }

    /// Set the response content
    pub fn content<S: Into<String>>(mut self, content: S) -> Self {
        self.content = content.into();
        self
    }

    /// Set the provider
    pub fn provider(mut self, provider: Provider) -> Self {
        self.provider = provider;
        self
    }

    /// Set the model
    pub fn model<S: Into<String>>(mut self, model: S) -> Self {
        self.model = model.into();
        self
    }

    /// Set tokens used
    pub fn tokens_used(mut self, tokens: u32) -> Self {
        self.tokens_used = Some(tokens);
        self
    }

    /// Set response time
    pub fn response_time(mut self, duration: Duration) -> Self {
        self.response_time = duration;
        self
    }

    /// Set metadata
    pub fn metadata(mut self, metadata: ResponseMetadata) -> Self {
        self.metadata = metadata;
        self
    }

    /// Build the response
    pub fn build(self) -> ChatResponse {
        ChatResponse::new(
            self.content,
            self.provider,
            self.model,
            self.tokens_used,
            self.response_time,
        ).with_metadata(self.metadata)
    }
}

impl Default for ResponseBuilder {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_chat_response_creation() {
        let response = ChatResponse::new(
            "Hello, world!".to_string(),
            Provider::OpenAI,
            "gpt-4".to_string(),
            Some(10),
            Duration::from_millis(500),
        );

        assert_eq!(response.content, "Hello, world!");
        assert_eq!(response.provider, Provider::OpenAI);
        assert_eq!(response.model, "gpt-4");
        assert_eq!(response.tokens_used, Some(10));
        assert_eq!(response.content_length(), 13);
        assert_eq!(response.word_count(), 2);
        assert!(response.is_complete());
    }

    #[test]
    fn test_incomplete_response_detection() {
        let incomplete = ChatResponse::new(
            "This is incomplete...".to_string(),
            Provider::OpenAI,
            "gpt-4".to_string(),
            None,
            Duration::from_millis(100),
        );
        assert!(!incomplete.is_complete());

        let complete = ChatResponse::new(
            "This is complete.".to_string(),
            Provider::OpenAI,
            "gpt-4".to_string(),
            None,
            Duration::from_millis(100),
        );
        assert!(complete.is_complete());
    }

    #[test]
    fn test_stream_chunk() {
        let stream_id = Uuid::new_v4();
        let chunk = StreamChunk::new(
            stream_id,
            "Hello".to_string(),
            0,
            false,
        );

        assert_eq!(chunk.stream_id, stream_id);
        assert_eq!(chunk.content, "Hello");
        assert_eq!(chunk.chunk_index, 0);
        assert!(!chunk.is_final);
        assert_eq!(chunk.size(), 5);
        assert!(!chunk.is_empty());
    }

    #[test]
    fn test_stream_statistics() {
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
    }

    #[test]
    fn test_response_builder() {
        let response = ResponseBuilder::new()
            .content("Test response")
            .provider(Provider::Claude)
            .model("claude-3-opus")
            .tokens_used(15)
            .build();

        assert_eq!(response.content, "Test response");
        assert_eq!(response.provider, Provider::Claude);
        assert_eq!(response.model, "claude-3-opus");
        assert_eq!(response.tokens_used, Some(15));
    }
}