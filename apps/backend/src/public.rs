use std::{net::SocketAddr, path::PathBuf, sync::Arc, time::Duration};

use axum::{
    Router,
    extract::{
        State, WebSocketUpgrade,
        ws::{Message, WebSocket},
    },
    http::StatusCode,
    response::Response,
    routing::get,
};
use serde_json::{Value, json};
use tokio::time::{MissedTickBehavior, interval, timeout};
use tower_http::services::{ServeDir, ServeFile};

use crate::{AppState, model::Snapshot};

pub async fn serve(
    address: SocketAddr,
    frontend: PathBuf,
    state: Arc<AppState>,
) -> std::io::Result<()> {
    let index = frontend.join("index.html");
    let api = Router::new()
        .route("/status", get(upgrade))
        .fallback(|| async { StatusCode::NOT_FOUND });
    let app = Router::new()
        .nest("/api", api)
        .fallback_service(ServeDir::new(frontend).fallback(ServeFile::new(index)))
        .with_state(state);
    let listener = tokio::net::TcpListener::bind(address).await?;
    tracing::info!(%address, "public HTTP and WebSocket server listening");
    axum::serve(listener, app).await
}

pub async fn upgrade(ws: WebSocketUpgrade, State(state): State<Arc<AppState>>) -> Response {
    ws.max_message_size(1024)
        .max_frame_size(1024)
        .on_upgrade(move |socket| connection(socket, state))
}

async fn connection(mut socket: WebSocket, state: Arc<AppState>) {
    let mut updates = state.updates.subscribe();
    let mut previous = updates.borrow_and_update().clone();
    if !send(
        &mut socket,
        Message::Text(
            json!({
                "type": "snapshot", "data": &*previous,
            })
            .to_string()
            .into(),
        ),
    )
    .await
    {
        return;
    }

    let mut heartbeat = interval(Duration::from_secs(30));
    heartbeat.set_missed_tick_behavior(MissedTickBehavior::Delay);
    heartbeat.tick().await;
    let mut awaiting_pong = false;
    loop {
        tokio::select! {
            changed = updates.changed() => {
                if changed.is_err() {
                    break;
                }
                let next = updates.borrow_and_update().clone();
                let patch = changes(&previous, &next);
                if !send(&mut socket, Message::Text(patch.to_string().into())).await {
                    break;
                }
                previous = next;
            }
            message = socket.recv() => {
                match message {
                    Some(Ok(Message::Pong(_))) => awaiting_pong = false,
                    Some(Ok(Message::Ping(_))) => {},
                    _ => break,
                }
            }
            _ = heartbeat.tick() => {
                if awaiting_pong || !send(&mut socket, Message::Ping(Vec::new().into())).await {
                    break;
                }
                awaiting_pong = true;
            }
        }
    }
}

async fn send(socket: &mut WebSocket, message: Message) -> bool {
    // A slow reader must not keep an unbounded backlog or retain a task forever.
    matches!(
        timeout(Duration::from_secs(10), socket.send(message)).await,
        Ok(Ok(()))
    )
}

fn changes(previous: &Snapshot, next: &Snapshot) -> Value {
    // Configuration is immutable until restart. Names, URLs and logos travel only
    // in the initial snapshot; later frames contain changed fields keyed by ID.
    let services: Vec<_> = previous
        .categories
        .iter()
        .zip(&next.categories)
        .flat_map(|(old, new)| old.services.iter().zip(&new.services))
        .filter_map(|(old, new)| {
            let old = serde_json::to_value(old).expect("service is serializable");
            let mut patch = serde_json::to_value(new).expect("service is serializable");
            let fields = patch.as_object_mut().expect("service is an object");
            fields.retain(|key, value| key == "id" || old.get(key) != Some(value));
            (fields.len() > 1).then_some(patch)
        })
        .collect();
    let incidents: Vec<_> = next
        .incidents
        .iter()
        .filter(|incident| !previous.incidents.contains(incident))
        .collect();
    let removed: Vec<_> = previous
        .incidents
        .iter()
        .filter(|old| !next.incidents.iter().any(|new| new.id == old.id))
        .map(|incident| incident.id)
        .collect();
    let mut patch = json!({"type": "update", "generatedAt": next.generated_at});
    if !services.is_empty() {
        patch["services"] = json!(services);
    }
    if !incidents.is_empty() {
        patch["incidents"] = json!(incidents);
    }
    if !removed.is_empty() {
        patch["removedIncidents"] = json!(removed);
    }
    patch
}
