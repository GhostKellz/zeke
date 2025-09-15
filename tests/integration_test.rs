use zeke::{ZekeApi, ZekeResult};

#[tokio::test]
async fn test_zeke_api_creation() -> ZekeResult<()> {
    // Test basic API creation
    let api = ZekeApi::new().await?;

    // Test provider listing
    let providers = api.list_providers().await?;
    println!("Available providers: {:?}", providers);

    // Test provider status
    let status = api.get_provider_status().await;
    println!("Provider status: {:?}", status);

    Ok(())
}

#[tokio::test]
async fn test_git_integration() -> ZekeResult<()> {
    #[cfg(feature = "git")]
    {
        let api = ZekeApi::new().await?;
        let git_manager = api.git()?;

        // Test git status
        match git_manager.status().await {
            Ok(status) => {
                println!("Git status: {:?}", status);
            }
            Err(e) => {
                println!("Git not available (expected in some environments): {}", e);
            }
        }
    }

    Ok(())
}

#[cfg(not(feature = "git"))]
#[tokio::test]
async fn test_basic_functionality_without_git() -> ZekeResult<()> {
    let api = ZekeApi::new().await?;

    // Test basic provider operations
    let providers = api.list_providers().await?;
    assert!(!providers.is_empty(), "Should have at least some providers configured");

    Ok(())
}