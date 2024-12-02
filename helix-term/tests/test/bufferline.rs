use super::*;

use std::time::Duration;

use helix_term::application::Application;
use helix_view::{
    editor::{Action, BufferLine},
    input::parse_macro,
    view,
};
use tokio_stream::wrappers::UnboundedReceiverStream;

#[cfg(windows)]
use crossterm::event::KeyModifiers as MouseModifiers;
#[cfg(windows)]
use crossterm::event::{Event, KeyEvent, MouseButton, MouseEvent, MouseEventKind};
#[cfg(not(windows))]
use termina::event::{
    Event, KeyEvent, Modifiers as MouseModifiers, MouseButton, MouseEvent, MouseEventKind,
};

fn app_with_buffers(names: &[&str]) -> anyhow::Result<(tempfile::TempDir, Application)> {
    let dir = tempfile::tempdir()?;
    let mut config = test_config();
    config.editor.bufferline = BufferLine::Multiple;
    let mut builder = AppBuilder::new().with_config(config);
    for name in names {
        let path = dir.path().join(name);
        std::fs::write(&path, "text\n")?;
        builder = builder.with_file(path, None);
    }
    Ok((dir, builder.build()?))
}

async fn send_events(
    app: &mut Application,
    events: impl IntoIterator<Item = Event>,
) -> anyhow::Result<()> {
    let (tx, rx) = tokio::sync::mpsc::unbounded_channel();
    for event in events {
        tx.send(Ok(event))?;
    }
    let mut stream = UnboundedReceiverStream::new(rx);
    assert!(
        tokio::time::timeout(
            Duration::from_secs(5),
            app.event_loop_until_idle(&mut stream)
        )
        .await?,
        "application exited while processing test events"
    );
    Ok(())
}

async fn send_keys(app: &mut Application, keys: &str) -> anyhow::Result<()> {
    send_events(
        app,
        parse_macro(keys)?
            .into_iter()
            .map(|key| Event::Key(KeyEvent::from(key))),
    )
    .await
}

async fn click(app: &mut Application, column: u16) -> anyhow::Result<()> {
    send_events(
        app,
        [Event::Mouse(MouseEvent {
            kind: MouseEventKind::Down(MouseButton::Left),
            column,
            row: 0,
            modifiers: MouseModifiers::empty(),
        })],
    )
    .await
}

#[tokio::test(flavor = "multi_thread")]
async fn clicking_tabs_replaces_the_document_in_the_focused_split() -> anyhow::Result<()> {
    let (dir, mut app) = app_with_buffers(&["a", "b"])?;
    let first = app
        .editor
        .document_id_by_path(&dir.path().join("a"))
        .unwrap();
    let second = app
        .editor
        .document_id_by_path(&dir.path().join("b"))
        .unwrap();
    app.editor.switch(second, Action::VerticalSplit);
    let focused_view = view!(app.editor).id;
    send_keys(&mut app, "<esc>").await?;

    click(&mut app, 1).await?;
    assert_eq!(view!(app.editor).doc, first);
    assert_eq!(view!(app.editor).id, focused_view);
    assert_eq!(app.editor.tree.views().count(), 2);

    click(&mut app, 4).await?;
    assert_eq!(view!(app.editor).doc, second);
    click(&mut app, 20).await?;
    assert_eq!(
        view!(app.editor).doc,
        second,
        "blank space must not switch buffers"
    );
    test_key_sequence(&mut app, Some(":qa!<ret>"), None, true).await
}

#[tokio::test(flavor = "multi_thread")]
async fn clicking_a_truncated_unicode_tab_uses_screen_columns() -> anyhow::Result<()> {
    let long_name = format!("{}.txt", "界".repeat(80));
    let (dir, mut app) = app_with_buffers(&["a", &long_name, "c"])?;
    let first = app
        .editor
        .document_id_by_path(&dir.path().join("a"))
        .unwrap();
    let second = app
        .editor
        .document_id_by_path(&dir.path().join(&long_name))
        .unwrap();
    send_keys(&mut app, "<esc>").await?;

    // The integration backend has 120 columns. The second tab is truncated;
    // column 119 is the trailing cell of a double-width grapheme.
    click(&mut app, 119).await?;
    assert_eq!(view!(app.editor).doc, second);
    click(&mut app, 3).await?;
    assert_eq!(view!(app.editor).doc, second);
    click(&mut app, 2).await?;
    assert_eq!(view!(app.editor).doc, first);
    test_key_sequence(&mut app, None, None, false).await
}

#[tokio::test(flavor = "multi_thread")]
async fn hiding_the_bufferline_disables_previous_mouse_targets() -> anyhow::Result<()> {
    let (dir, mut app) = app_with_buffers(&["a", "b"])?;
    let first = app
        .editor
        .document_id_by_path(&dir.path().join("a"))
        .unwrap();
    let second = app
        .editor
        .document_id_by_path(&dir.path().join("b"))
        .unwrap();
    send_keys(&mut app, "<esc>").await?;
    click(&mut app, 4).await?;
    assert_eq!(view!(app.editor).doc, second);
    click(&mut app, 1).await?;
    assert_eq!(view!(app.editor).doc, first);

    send_keys(&mut app, ":set-option bufferline never<ret>").await?;
    click(&mut app, 4).await?;
    assert_eq!(view!(app.editor).doc, first);

    send_keys(&mut app, ":set-option bufferline multiple<ret>").await?;
    click(&mut app, 4).await?;
    assert_eq!(view!(app.editor).doc, second);
    test_key_sequence(&mut app, None, None, false).await
}
