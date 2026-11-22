//! User and lobby names as clients may choose them.

/// Trims and accepts 1 to `max_chars` characters without control characters.
pub(crate) fn clean_name(name: &str, max_chars: usize) -> Option<String> {
    let trimmed = name.trim();
    let length = trimmed.chars().count();
    let printable = !trimmed.chars().any(char::is_control);
    (printable && (1..=max_chars).contains(&length)).then(|| trimmed.to_string())
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
}
