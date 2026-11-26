//! User and lobby names as clients may choose them.

/// Unicode general category Cf (format), written out to avoid a dependency for one table.
const FORMAT_RANGES: &[(u32, u32)] = &[
    (0x00AD, 0x00AD),
    (0x0600, 0x0605),
    (0x061C, 0x061C),
    (0x06DD, 0x06DD),
    (0x070F, 0x070F),
    (0x0890, 0x0891),
    (0x08E2, 0x08E2),
    (0x180E, 0x180E),
    (0x200B, 0x200F),
    (0x202A, 0x202E),
    (0x2060, 0x2064),
    (0x2066, 0x206F),
    (0xFEFF, 0xFEFF),
    (0xFFF9, 0xFFFB),
    (0x110BD, 0x110BD),
    (0x110CD, 0x110CD),
    (0x13430, 0x1343F),
    (0x1BCA0, 0x1BCA3),
    (0x1D173, 0x1D17A),
    (0xE0001, 0xE0001),
    (0xE0020, 0xE007F),
];

/// Zl, Zp, and characters that render blank without being whitespace or Cf.
const BLANK_RANGES: &[(u32, u32)] = &[
    (0x034F, 0x034F),
    (0x115F, 0x1160),
    (0x17B4, 0x17B5),
    (0x2028, 0x2029),
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

fn is_forbidden(character: char) -> bool {
    character.is_control()
        || in_ranges(character, FORMAT_RANGES)
        || in_ranges(character, BLANK_RANGES)
}

/// Trims and accepts 1 to `max_chars` characters without control, format or filler characters and
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
