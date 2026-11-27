use std::time::Duration;

use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use hmac::{Hmac, Mac};
use serde::{Deserialize, Serialize};
use settler_island_protocol::UserKind;

use super::UserId;
use sha2::Sha256;

use crate::config::SessionSecret;

/// Marks a guest token so it is never mistaken for a Keycloak JWT.
pub(crate) const GUEST_TOKEN_PREFIX: &str = "guest.";
pub(crate) const GUEST_TOKEN_LIFETIME: Duration = Duration::from_secs(30 * 24 * 60 * 60);

#[derive(Debug, Serialize, Deserialize)]
struct GuestClaims {
    id: UserId,
    name: String,
    kind: UserKind,
    /// Unix seconds.
    expires: u64,
}

/// Who a guest token names.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct Guest {
    pub id: UserId,
    pub name: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, thiserror::Error)]
pub(crate) enum GuestTokenError {
    #[error("the guest token is malformed")]
    Malformed,
    #[error("the guest token signature does not match")]
    BadSignature,
    #[error("the guest token has expired")]
    Expired,
}

/// Issues and checks `guest.<payload>.<signature>` tokens, both parts base64url, signed with HMAC-SHA256.
pub(crate) struct GuestTokens {
    secret: SessionSecret,
}

impl GuestTokens {
    pub(crate) fn new(secret: SessionSecret) -> GuestTokens {
        GuestTokens { secret }
    }

    /// `now` is in Unix seconds.
    pub(crate) fn issue(&self, guest: &Guest, now: u64) -> String {
        let claims = GuestClaims {
            id: guest.id.clone(),
            name: guest.name.clone(),
            kind: UserKind::Guest,
            expires: now + GUEST_TOKEN_LIFETIME.as_secs(),
        };
        // Serializing a struct of strings and integers cannot fail.
        let payload = URL_SAFE_NO_PAD.encode(serde_json::to_vec(&claims).unwrap_or_default());
        let signature = URL_SAFE_NO_PAD.encode(self.mac(&payload).finalize().into_bytes());
        format!("{GUEST_TOKEN_PREFIX}{payload}.{signature}")
    }

    pub(crate) fn verify(&self, token: &str, now: u64) -> Result<Guest, GuestTokenError> {
        let body = token
            .strip_prefix(GUEST_TOKEN_PREFIX)
            .ok_or(GuestTokenError::Malformed)?;
        let (payload, signature) = body.split_once('.').ok_or(GuestTokenError::Malformed)?;
        let signature = URL_SAFE_NO_PAD
            .decode(signature)
            .map_err(|_| GuestTokenError::Malformed)?;
        self.mac(payload)
            .verify_slice(&signature)
            .map_err(|_| GuestTokenError::BadSignature)?;
        let claims: GuestClaims = URL_SAFE_NO_PAD
            .decode(payload)
            .ok()
            .and_then(|json| serde_json::from_slice(&json).ok())
            .ok_or(GuestTokenError::Malformed)?;
        if claims.expires <= now {
            return Err(GuestTokenError::Expired);
        }
        Ok(Guest {
            id: claims.id,
            name: claims.name,
        })
    }

    fn mac(&self, payload: &str) -> Hmac<Sha256> {
        let mut mac = <Hmac<Sha256> as Mac>::new_from_slice(self.secret.bytes())
            .unwrap_or_else(|_| unreachable!("HMAC accepts keys of any length"));
        mac.update(payload.as_bytes());
        mac
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const NOW: u64 = 1_800_000_000;

    fn signer(first_byte: u8) -> GuestTokens {
        GuestTokens::new(
            SessionSecret::new((first_byte..first_byte + 32).collect::<Vec<u8>>()).unwrap(),
        )
    }

    fn ada() -> Guest {
        Guest {
            id: UserId("u-1".to_string()),
            name: "Ada".to_string(),
        }
    }

    #[test]
    fn a_token_round_trips_until_it_expires() {
        let tokens = signer(1);
        let token = tokens.issue(&ada(), NOW);
        let lifetime = GUEST_TOKEN_LIFETIME.as_secs();

        assert_eq!(tokens.verify(&token, NOW + lifetime - 1), Ok(ada()));
        assert_eq!(
            tokens.verify(&token, NOW + lifetime),
            Err(GuestTokenError::Expired)
        );
    }

    #[test]
    fn tampered_or_foreign_tokens_are_rejected() {
        let tokens = signer(1);
        let token = tokens.issue(&ada(), NOW);
        let (payload, signature) = token
            .strip_prefix(GUEST_TOKEN_PREFIX)
            .unwrap()
            .split_once('.')
            .unwrap();
        let mut claims: serde_json::Value =
            serde_json::from_slice(&URL_SAFE_NO_PAD.decode(payload).unwrap()).unwrap();
        claims["id"] = serde_json::json!("someone-else");
        let forged_payload = URL_SAFE_NO_PAD.encode(claims.to_string());
        let tampered = format!("{GUEST_TOKEN_PREFIX}{forged_payload}.{signature}");

        assert_eq!(
            tokens.verify(&tampered, NOW),
            Err(GuestTokenError::BadSignature)
        );
        assert_eq!(
            signer(2).verify(&token, NOW),
            Err(GuestTokenError::BadSignature)
        );
        assert_eq!(
            tokens.verify("guest.nodot", NOW),
            Err(GuestTokenError::Malformed)
        );
    }
}
