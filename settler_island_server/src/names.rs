//! User and lobby names as clients may choose them.

use unicode_general_category::{get_general_category, GeneralCategory};

/// Letters and marks that render blank (fillers); no general category singles them out.
const BLANK_RANGES: &[(u32, u32)] = &[
    (0x034F, 0x034F),
    (0x115F, 0x1160),
    (0x17B4, 0x17B5),
    (0x2800, 0x2800),
    (0x3164, 0x3164),
    (0xFFA0, 0xFFA0),
];

fn in_ranges(character: char, ranges: &[(u32, u32)]) -> bool {
    let code = u32::from(character);
    ranges
        .iter()
        .any(|&(first, last)| (first..=last).contains(&code))
}

/// Control, format (bidi overrides, zero-width), line and paragraph separators, private use and unassigned
/// characters, plus the blank fillers.
fn is_forbidden(character: char) -> bool {
    let invisible = matches!(
        get_general_category(character),
        GeneralCategory::Control
            | GeneralCategory::Format
            | GeneralCategory::LineSeparator
            | GeneralCategory::ParagraphSeparator
            | GeneralCategory::PrivateUse
            | GeneralCategory::Unassigned
    );
    invisible || in_ranges(character, BLANK_RANGES)
}

/// Trims and accepts 1 to `max_chars` characters without forbidden characters (see `is_forbidden`) and
/// with at least one non-whitespace one (bidi overrides and zero-width characters spoof names).
pub(crate) fn clean_name(name: &str, max_chars: usize) -> Option<String> {
    let trimmed = name.trim();
    let length = trimmed.chars().count();
    let clean = !trimmed.chars().any(is_forbidden);
    (clean && (1..=max_chars).contains(&length)).then(|| trimmed.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn names_are_trimmed_and_bounded_in_characters_not_bytes() {
        assert_eq!(clean_name("  Ada ", 24), Some("Ada".to_string()));
        assert_eq!(clean_name("   ", 24), None);
        assert_eq!(clean_name("", 24), None);
        assert_eq!(clean_name("bad\nname", 24), None);
        assert_eq!(clean_name(&"ä".repeat(24), 24), Some("ä".repeat(24)));
        assert_eq!(clean_name(&"a".repeat(25), 24), None);
    }

    #[test]
    fn spoofing_characters_are_rejected() {
        for rejected in [
            "\u{202E}evil",
            "a\u{2066}b",
            "a\u{2069}",
            "evil\u{200B}",
            "a\u{FEFF}b",
            "a\u{00AD}b",
            "a\u{2028}b",
            "\u{3164}",
            "a\u{3164}",
            "\u{200B}\u{200D}",
            "\u{2800}",
            // Private use and unassigned code points render as anything a font chooses.
            "a\u{E000}b",
            "a\u{0378}b",
        ] {
            assert_eq!(clean_name(rejected, 24), None, "{rejected:?}");
        }
    }

    #[test]
    fn ordinary_non_latin_names_pass() {
        for accepted in ["Jürgen Groß", "田中太郎", "محمد", "Ada Lovelace"] {
            assert_eq!(clean_name(accepted, 24), Some(accepted.to_string()));
        }
    }
}
