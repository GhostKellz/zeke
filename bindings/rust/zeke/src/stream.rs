//! Async streaming support for Zeke

#[cfg(feature = "async")]
use crate::{
    ffi_utils::CStringHolder,
    error::{check_result_with_context, Error, Result},
    response::StreamChunk,
    Zeke,
};
use futures::{Stream, StreamExt};
use std::pin::Pin;
use std::task::{Context, Poll};
use tokio::sync::mpsc;
use uuid::Uuid;
use zeke_sys::*;

/// Async stream wrapper for Zeke streaming responses
#[cfg(feature = "async")]
pub struct ZekeStream {
    receiver: mpsc::UnboundedReceiver<Result<StreamChunk>>,
    stream_id: Uuid,
    completed: bool,
}

#[cfg(feature = "async")]
impl ZekeStream {
    /// Create a new streaming chat session
    pub(crate) async fn new(zeke: &Zeke, message: &str) -> Result<Self> {
        let stream_id = Uuid::new_v4();
        let (sender, receiver) = mpsc::unbounded_channel();
        
        let message_cstr = CStringHolder::new(message)?;
        
        // Context for the callback
        struct StreamContext {
            sender: mpsc::UnboundedSender<Result<StreamChunk>>,
            stream_id: Uuid,
            chunk_index: u32,
        }
        
        let mut context = Box::new(StreamContext {
            sender,
            stream_id,
            chunk_index: 0,
        });
        
        unsafe extern "C" fn stream_callback(
            chunk: *const ZekeStreamChunk,
            user_data: *mut std::ffi::c_void,
        ) {
            if chunk.is_null() || user_data.is_null() {
                return;
            }
            
            let context = &mut *(user_data as *mut StreamContext);
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
            
            // Send the result (ignore send errors - receiver might be dropped)
            let _ = context.sender.send(result);
        }
        
        // Start the streaming in a background task
        let handle = zeke.handle;
        let context_ptr = Box::into_raw(context);
        
        tokio::spawn(async move {
            let result = unsafe {
                zeke_chat_stream(
                    handle,
                    message_cstr.as_ptr(),
                    Some(stream_callback),
                    context_ptr as *mut std::ffi::c_void,
                )
            };
            
            // Clean up the context
            unsafe {
                let _ = Box::from_raw(context_ptr);
            }
            
            // If there was an error, send it through the channel
            if let Err(e) = check_result_with_context(result) {
                // The context is already cleaned up, so we can't send through sender
                // This is a limitation of the current design
                tracing::error!("Streaming error: {}", e);
            }
        });
        
        Ok(Self {
            receiver,
            stream_id,
            completed: false,
        })
    }
    
    /// Get the stream ID
    pub fn stream_id(&self) -> Uuid {
        self.stream_id
    }
    
    /// Check if the stream has completed
    pub fn is_completed(&self) -> bool {
        self.completed
    }
    
    /// Collect all remaining chunks into a vector
    pub async fn collect_remaining(mut self) -> Vec<Result<StreamChunk>> {
        let mut chunks = Vec::new();
        
        while let Some(chunk) = self.next().await {
            chunks.push(chunk);
        }
        
        chunks
    }
    
    /// Collect all chunks and concatenate their content
    pub async fn collect_content(mut self) -> Result<String> {
        let mut content = String::new();
        let mut errors = Vec::new();
        
        while let Some(chunk_result) = self.next().await {
            match chunk_result {
                Ok(chunk) => content.push_str(&chunk.content),
                Err(e) => errors.push(e),
            }
        }
        
        if !errors.is_empty() {
            return Err(Error::custom(format!(
                "Streaming errors: {:?}",
                errors
            )));
        }
        
        Ok(content)
    }
    
    /// Create statistics for the stream
    pub async fn with_statistics(mut self) -> (Vec<StreamChunk>, crate::response::StreamStatistics) {
        let mut chunks = Vec::new();
        
        while let Some(chunk_result) = self.next().await {
            if let Ok(chunk) = chunk_result {
                chunks.push(chunk);
            }
        }
        
        let statistics = crate::response::StreamStatistics::from_chunks(&chunks);
        (chunks, statistics)
    }
}

#[cfg(feature = "async")]
impl Stream for ZekeStream {
    type Item = Result<StreamChunk>;
    
    fn poll_next(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Option<Self::Item>> {
        match self.receiver.poll_recv(cx) {
            Poll::Ready(Some(chunk_result)) => {
                // Check if this is the final chunk
                if let Ok(ref chunk) = chunk_result {
                    if chunk.is_final {
                        self.completed = true;
                    }
                }
                Poll::Ready(Some(chunk_result))
            }
            Poll::Ready(None) => {
                self.completed = true;
                Poll::Ready(None)
            }
            Poll::Pending => Poll::Pending,
        }
    }
}

#[cfg(feature = "async")]
impl Drop for ZekeStream {
    fn drop(&mut self) {
        if !self.completed {
            tracing::debug!("ZekeStream dropped before completion");
        }
    }
}

/// Stream utilities
#[cfg(feature = "async")]
pub mod utils {
    use super::*;
    use futures::stream::{self, BoxStream};
    
    /// Create a mock stream for testing
    pub fn mock_stream(chunks: Vec<String>) -> BoxStream<'static, Result<StreamChunk>> {
        let stream_id = Uuid::new_v4();
        let chunk_stream = stream::iter(chunks.into_iter().enumerate().map(move |(i, content)| {
            let is_final = i == chunks.len() - 1;
            Ok(StreamChunk::new(stream_id, content, i as u32, is_final))
        }));
        
        Box::pin(chunk_stream)
    }
    
    /// Combine multiple streams into one
    pub fn combine_streams<S>(streams: Vec<S>) -> BoxStream<'static, Result<StreamChunk>>
    where
        S: Stream<Item = Result<StreamChunk>> + Send + 'static,
    {
        let combined = stream::select_all(streams);
        Box::pin(combined)
    }
    
    /// Rate limit a stream
    pub fn rate_limit<S>(
        stream: S,
        duration: std::time::Duration,
    ) -> BoxStream<'static, Result<StreamChunk>>
    where
        S: Stream<Item = Result<StreamChunk>> + Send + 'static,
    {
        let rate_limited = stream.then(move |item| async move {
            tokio::time::sleep(duration).await;
            item
        });
        
        Box::pin(rate_limited)
    }
    
    /// Buffer a stream to reduce backpressure
    pub fn buffer<S>(
        stream: S,
        buffer_size: usize,
    ) -> BoxStream<'static, Result<StreamChunk>>
    where
        S: Stream<Item = Result<StreamChunk>> + Send + 'static,
    {
        let buffered = stream.buffered(buffer_size);
        Box::pin(buffered)
    }
}

#[cfg(all(test, feature = "async"))]
mod tests {
    use super::*;
    use futures::StreamExt;
    
    #[tokio::test]
    async fn test_mock_stream() {
        let chunks = vec!["Hello".to_string(), " ".to_string(), "World!".to_string()];
        let mut stream = utils::mock_stream(chunks);
        
        let mut collected = String::new();
        let mut chunk_count = 0;
        
        while let Some(chunk_result) = stream.next().await {
            let chunk = chunk_result.unwrap();
            collected.push_str(&chunk.content);
            chunk_count += 1;
            
            if chunk.is_final {
                assert_eq!(chunk_count, 3);
                break;
            }
        }
        
        assert_eq!(collected, "Hello World!");
    }
    
    #[tokio::test]
    async fn test_collect_content() {
        let chunks = vec!["Hello".to_string(), " ".to_string(), "World!".to_string()];
        let stream = utils::mock_stream(chunks);
        
        let content = stream.collect_content().await.unwrap();
        assert_eq!(content, "Hello World!");
    }
    
    #[tokio::test]
    async fn test_rate_limiting() {
        use std::time::Instant;
        
        let chunks = vec!["A".to_string(), "B".to_string()];
        let stream = utils::mock_stream(chunks);
        let rate_limited = utils::rate_limit(stream, std::time::Duration::from_millis(100));
        
        let start = Instant::now();
        let _: Vec<_> = rate_limited.collect().await;
        let elapsed = start.elapsed();
        
        // Should take at least 200ms (2 chunks * 100ms delay each)
        assert!(elapsed >= std::time::Duration::from_millis(200));
    }
}