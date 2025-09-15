use crate::error::ZekeResult;
use tracing::info;

pub async fn handle_ask(question: String) -> ZekeResult<()> {
    info!("❓ Ask: {}", question);

    // TODO: Implement actual ask with provider manager
    println!("🤖 ZEKE: You asked: \"{}\"", question);
    println!("📝 (Provider integration coming soon...)");

    Ok(())
}