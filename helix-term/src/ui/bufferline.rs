use std::{ops::Range, path::PathBuf};

use helix_view::{
    document::SCRATCH_BUFFER_NAME, editor::BufferLine, graphics::Rect, DocumentId, Editor,
};
use tui::buffer::Buffer as Surface;

/// Keeps mouse targets in sync with the cells drawn on the bufferline.
#[derive(Default)]
pub(super) struct Bufferline {
    area: Rect,
    buffers: Vec<BufferInfo>,
}

struct BufferInfo {
    document_id: DocumentId,
    columns: Range<u16>,
}

pub(super) fn is_visible(editor: &Editor) -> bool {
    match editor.config().bufferline {
        BufferLine::Always => true,
        BufferLine::Multiple => editor.documents.len() > 1,
        BufferLine::Never => false,
    }
}

impl Bufferline {
    pub fn clear(&mut self) {
        self.area = Rect::default();
        self.buffers.clear();
    }

    pub fn contains(&self, row: u16, column: u16) -> bool {
        (self.area.y..self.area.bottom()).contains(&row)
            && (self.area.x..self.area.right()).contains(&column)
    }

    pub fn document_at(&self, column: u16) -> Option<DocumentId> {
        self.buffers
            .iter()
            .find(|buffer| buffer.columns.contains(&column))
            .map(|buffer| buffer.document_id)
    }

    pub fn render(&mut self, editor: &Editor, viewport: Rect, surface: &mut Surface) {
        self.clear();
        self.area = viewport.intersection(surface.area);
        if self.area.width == 0 || self.area.height == 0 {
            return;
        }

        let scratch = PathBuf::from(SCRATCH_BUFFER_NAME);
        surface.clear_with(
            self.area,
            editor
                .theme
                .try_get("ui.bufferline.background")
                .unwrap_or_else(|| editor.theme.get("ui.statusline")),
        );

        let active = editor
            .theme
            .try_get("ui.bufferline.active")
            .unwrap_or_else(|| editor.theme.get("ui.statusline.active"));
        let inactive = editor
            .theme
            .try_get("ui.bufferline")
            .unwrap_or_else(|| editor.theme.get("ui.statusline.inactive"));

        let mut x = self.area.x;
        let current_doc = view!(editor).doc;
        for doc in editor.documents() {
            let fname = doc
                .path()
                .unwrap_or(&scratch)
                .file_name()
                .unwrap_or_default()
                .to_str()
                .unwrap_or_default();
            let style = if current_doc == doc.id() {
                active
            } else {
                inactive
            };
            let text = format!(" {}{} ", fname, if doc.is_modified() { "[+]" } else { "" });
            let start = x;
            x = surface
                .set_stringn(
                    x,
                    self.area.y,
                    &text,
                    (self.area.right() - x) as usize,
                    style,
                )
                .0;
            self.buffers.push(BufferInfo {
                document_id: doc.id(),
                columns: start..x,
            });
            if x >= self.area.right() {
                break;
            }
        }
    }
}
