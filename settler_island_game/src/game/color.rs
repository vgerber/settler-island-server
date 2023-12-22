use serde::Serialize;

#[derive(Serialize)]
pub struct Color {
    r: f32,
    g: f32,
    b: f32,
    a: f32,
}

impl Color {
    pub fn from(r: f32, b: f32, g: f32, a: f32) -> Self {
        Color {
            r: r,
            g: g,
            b: b,
            a: a,
        }
    }
}
