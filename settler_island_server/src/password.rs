use argon2::password_hash::{PasswordHash, PasswordHasher, PasswordVerifier, SaltString};
use argon2::Argon2;
use rand::RngCore;

#[derive(Debug, thiserror::Error)]
#[error("password hashing failed: {0}")]
pub(crate) struct HashError(argon2::password_hash::Error);

/// CPU heavy: call from `spawn_blocking`.
pub(crate) fn hash(password: &str) -> Result<String, HashError> {
    let mut salt = [0u8; 16];
    rand::rng().fill_bytes(&mut salt);
    let salt = SaltString::encode_b64(&salt).map_err(HashError)?;
    let hash = Argon2::default()
        .hash_password(password.as_bytes(), &salt)
        .map_err(HashError)?;
    Ok(hash.to_string())
}

/// CPU heavy: call from `spawn_blocking`. A malformed hash never matches.
pub(crate) fn verify(hash: &str, password: &str) -> bool {
    let Ok(parsed) = PasswordHash::new(hash) else {
        return false;
    };
    Argon2::default()
        .verify_password(password.as_bytes(), &parsed)
        .is_ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_the_original_password_verifies_and_salts_differ() {
        let first = hash("open sesame").unwrap();
        let second = hash("open sesame").unwrap();

        assert_ne!(first, second);
        assert!(!first.contains("open sesame"));
        assert!(verify(&first, "open sesame"));
        assert!(!verify(&first, "open sesame "));
        assert!(!verify("not a hash", "open sesame"));
    }
}
