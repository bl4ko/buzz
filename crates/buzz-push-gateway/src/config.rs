use base64::{engine::general_purpose::STANDARD, Engine as _};
use std::{collections::HashMap, net::SocketAddr, path::PathBuf};
use thiserror::Error;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ApnsEnvironment {
    Production,
    Sandbox,
}

#[derive(Debug, Clone)]
pub struct AppProfileConfig {
    pub app_attest_app_id: String,
    /// Exact Apple attestation environment accepted for enrollment.
    pub app_attest_environment: AppAttestEnvironment,
    pub apns_cert_path: PathBuf,
    pub apns_topic: String,
    pub apns_environment: ApnsEnvironment,
    pub live_activity: Option<LiveActivityCredentials>,
    pub qa_apns_base_url: Option<String>,
}

impl AppProfileConfig {
    pub fn apns_base_url(&self) -> &str {
        self.qa_apns_base_url
            .as_deref()
            .unwrap_or(match self.apns_environment {
                ApnsEnvironment::Production => "https://api.push.apple.com",
                ApnsEnvironment::Sandbox => "https://api.sandbox.push.apple.com",
            })
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LiveActivityCredentials {
    pub auth_key_path: PathBuf,
    pub key_id: String,
    pub team_id: String,
}

fn parse_live_activity(
    e: &HashMap<String, String>,
) -> Result<Option<LiveActivityCredentials>, ConfigError> {
    const KEYS: [&str; 3] = [
        "BUZZ_PUSH_DOGFOOD_APNS_AUTH_KEY_PATH",
        "BUZZ_PUSH_DOGFOOD_APNS_AUTH_KEY_ID",
        "BUZZ_PUSH_DOGFOOD_APNS_TEAM_ID",
    ];
    let values = KEYS.map(|key| e.get(key).map(String::as_str).filter(|v| !v.is_empty()));
    let [Some(path), Some(key_id), Some(team_id)] = values else {
        return match KEYS.iter().zip(values).find(|(_, value)| value.is_none()) {
            Some((key, _)) if values.iter().any(Option::is_some) => Err(ConfigError::Missing(key)),
            _ => Ok(None),
        };
    };
    let apple_id =
        |value: &str| value.len() == 10 && value.bytes().all(|b| b.is_ascii_alphanumeric());
    if !apple_id(key_id) {
        return Err(ConfigError::Invalid(KEYS[1]));
    }
    if !apple_id(team_id) {
        return Err(ConfigError::Invalid(KEYS[2]));
    }
    Ok(Some(LiveActivityCredentials {
        auth_key_path: PathBuf::from(path),
        key_id: key_id.to_owned(),
        team_id: team_id.to_owned(),
    }))
}

/// Apple App Attest environment, independent of the APNs transport environment.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AppAttestEnvironment {
    /// Distributed applications, also the default for personal development builds.
    Production,
    /// Development-signed applications in an explicitly opted-in gateway build.
    #[cfg(feature = "personal-dev-app-attest")]
    Development,
    #[cfg(feature = "qa-simulator")]
    Simulator,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct KeyConfig {
    pub id: String,
    pub key: Vec<u8>,
}

#[derive(Debug, Clone)]
pub struct Config {
    pub bind_addr: SocketAddr,
    pub health_addr: SocketAddr,
    pub max_grant_lifetime_seconds: i64,
    pub max_installation_lifetime_seconds: i64,
    pub endpoint_quota_window_seconds: i64,
    pub endpoint_quota_max_deliveries: i64,
    pub live_activity_quota_window_seconds: i64,
    pub live_activity_quota_max_deliveries: i64,
    /// Server-owned dogfood application identity and APNs transport.
    pub profile: AppProfileConfig,
    pub database_url: String,
    pub app_attest_root_cert_path: PathBuf,
    /// Ordered current key first, followed by decrypt-only predecessors.
    pub grant_keys: Vec<KeyConfig>,
    /// Independent token-custody keyring. These keys MUST NOT be reused for
    /// externally presented delivery capabilities.
    pub token_keys: Vec<KeyConfig>,
}

// Registered NIP-PL v1 App Attest audiences are protocol constants, not routing URLs.
/// Fixed NIP-PL v1 App Attest audience for installation enrollment.
pub const ENROLL_AUDIENCE: &str = "https://push.buzz.xyz/v1/installations";
/// Fixed NIP-PL v1 App Attest audience for creating a delegation.
pub const DELEGATE_AUDIENCE: &str = "https://push.buzz.xyz/v1/delegations";
/// Fixed NIP-PL v1 App Attest audience for rotating an installation endpoint.
pub const ROTATE_ENDPOINT_AUDIENCE: &str = "https://push.buzz.xyz/v1/installations/endpoint";
/// Fixed NIP-PL v1 App Attest audience for revoking a delegation.
pub const REVOKE_DELEGATION_AUDIENCE: &str = "https://push.buzz.xyz/v1/delegations/revoke";
/// Fixed NIP-PL v1 App Attest audience for revoking an installation.
pub const REVOKE_INSTALLATION_AUDIENCE: &str = "https://push.buzz.xyz/v1/installations/revoke";
pub const LIVE_ACTIVITY_AUDIENCE: &str = "https://push.buzz.xyz/v1/installations/live-activity";
pub const LIVE_ACTIVITY_UPDATE_AUDIENCE: &str =
    "https://push.buzz.xyz/v1/installations/live-activity/update-token";

#[derive(Debug, Error)]
pub enum ConfigError {
    #[error("missing required environment variable {0}")]
    Missing(&'static str),
    #[error("invalid environment variable {0}")]
    Invalid(&'static str),
}
fn parse_keyring(
    e: &HashMap<String, String>,
    variable: &'static str,
) -> Result<Vec<KeyConfig>, ConfigError> {
    let value = e
        .get(variable)
        .map(String::as_str)
        .filter(|value| !value.is_empty())
        .ok_or(ConfigError::Missing(variable))?;
    let keys = value
        .split(',')
        .map(|entry| {
            let (id, encoded) = entry
                .split_once(':')
                .filter(|(id, encoded)| !id.is_empty() && !encoded.is_empty())
                .ok_or(ConfigError::Invalid(variable))?;
            let key = STANDARD
                .decode(encoded)
                .map_err(|_| ConfigError::Invalid(variable))?;
            if key.len() != 32 {
                return Err(ConfigError::Invalid(variable));
            }
            Ok(KeyConfig {
                id: id.to_owned(),
                key,
            })
        })
        .collect::<Result<Vec<_>, _>>()?;
    if keys.is_empty() {
        return Err(ConfigError::Invalid(variable));
    }
    Ok(keys)
}

const QA_APNS_BASE_URL: &str = "BUZZ_PUSH_QA_APNS_BASE_URL";

fn parse_profile(e: &HashMap<String, String>) -> Result<AppProfileConfig, ConfigError> {
    let app_id_key = "BUZZ_PUSH_DOGFOOD_APP_ATTEST_APP_ID";
    let cert_key = "BUZZ_PUSH_DOGFOOD_APNS_CERT_PATH";
    let topic_key = "BUZZ_PUSH_DOGFOOD_APNS_TOPIC";
    let environment_key = "BUZZ_PUSH_DOGFOOD_APNS_ENVIRONMENT";
    let required = |key: &'static str| {
        e.get(key)
            .map(String::as_str)
            .filter(|value| !value.is_empty())
            .ok_or(ConfigError::Missing(key))
    };
    let app_attest_app_id = required(app_id_key)?.to_owned();
    let app_attest_environment = match e
        .get("BUZZ_PUSH_APP_ATTEST_ENVIRONMENT")
        .map(String::as_str)
    {
        None | Some("production") => AppAttestEnvironment::Production,
        #[cfg(feature = "personal-dev-app-attest")]
        Some("development") => AppAttestEnvironment::Development,
        #[cfg(feature = "qa-simulator")]
        Some("simulator") => AppAttestEnvironment::Simulator,
        Some(_) => return Err(ConfigError::Invalid("BUZZ_PUSH_APP_ATTEST_ENVIRONMENT")),
    };
    let qa_apns_base_url = e
        .get(QA_APNS_BASE_URL)
        .filter(|value| !value.is_empty())
        .cloned();
    if qa_apns_base_url.is_some() && !cfg!(feature = "qa-simulator") {
        return Err(ConfigError::Invalid(QA_APNS_BASE_URL));
    }
    let apns_topic = required(topic_key)?.to_owned();
    let apns_cert_path = PathBuf::from(required(cert_key)?);
    let apns_environment = match e.get(environment_key).map(String::as_str) {
        None | Some("production") => ApnsEnvironment::Production,
        Some("sandbox") => ApnsEnvironment::Sandbox,
        Some(_) => return Err(ConfigError::Invalid(environment_key)),
    };
    Ok(AppProfileConfig {
        app_attest_app_id,
        app_attest_environment,
        apns_cert_path,
        apns_topic,
        apns_environment,
        live_activity: parse_live_activity(e)?,
        qa_apns_base_url,
    })
}

impl Config {
    pub fn from_env() -> Result<Self, ConfigError> {
        Self::from_map(&std::env::vars().collect())
    }
    pub fn from_map(e: &HashMap<String, String>) -> Result<Self, ConfigError> {
        fn req<'a>(
            e: &'a HashMap<String, String>,
            k: &'static str,
        ) -> Result<&'a str, ConfigError> {
            e.get(k)
                .map(String::as_str)
                .filter(|v| !v.is_empty())
                .ok_or(ConfigError::Missing(k))
        }
        let grant_keys = parse_keyring(e, "BUZZ_PUSH_GRANT_KEYS")?;
        let token_keys = parse_keyring(e, "BUZZ_PUSH_TOKEN_KEYS")?;
        if grant_keys.iter().any(|grant| {
            token_keys
                .iter()
                .any(|token| grant.id == token.id || grant.key == token.key)
        }) {
            return Err(ConfigError::Invalid("BUZZ_PUSH_TOKEN_KEYS"));
        }
        let max_grant_lifetime_seconds = req(e, "BUZZ_PUSH_MAX_GRANT_LIFETIME_SECONDS")?
            .parse::<i64>()
            .ok()
            .filter(|seconds| (1..=31_536_000).contains(seconds))
            .ok_or(ConfigError::Invalid("BUZZ_PUSH_MAX_GRANT_LIFETIME_SECONDS"))?;
        let max_installation_lifetime_seconds = e
            .get("BUZZ_PUSH_MAX_INSTALLATION_LIFETIME_SECONDS")
            .map(String::as_str)
            .unwrap_or("7776000")
            .parse::<i64>()
            .ok()
            .filter(|seconds| (1..=31_536_000).contains(seconds))
            .ok_or(ConfigError::Invalid(
                "BUZZ_PUSH_MAX_INSTALLATION_LIFETIME_SECONDS",
            ))?;
        let bounded_positive = |key: &'static str, default: i64, max: i64| {
            e.get(key)
                .map(String::as_str)
                .unwrap_or("")
                .parse::<i64>()
                .ok()
                .or((!e.contains_key(key)).then_some(default))
                .filter(|value| (1..=max).contains(value))
                .ok_or(ConfigError::Invalid(key))
        };
        let endpoint_quota_window_seconds =
            bounded_positive("BUZZ_PUSH_ENDPOINT_QUOTA_WINDOW_SECONDS", 10, 86_400)?;
        let endpoint_quota_max_deliveries =
            bounded_positive("BUZZ_PUSH_ENDPOINT_QUOTA_MAX_DELIVERIES", 10, 10_000)?;
        let live_activity_quota_window_seconds =
            bounded_positive("BUZZ_PUSH_LIVE_ACTIVITY_QUOTA_WINDOW_SECONDS", 10, 86_400)?;
        let live_activity_quota_max_deliveries =
            bounded_positive("BUZZ_PUSH_LIVE_ACTIVITY_QUOTA_MAX_DELIVERIES", 10, 10_000)?;
        let profile = parse_profile(e)?;
        let bind_addr = e
            .get("BUZZ_PUSH_BIND_ADDR")
            .map(String::as_str)
            .unwrap_or("0.0.0.0:8080")
            .parse::<SocketAddr>()
            .map_err(|_| ConfigError::Invalid("BUZZ_PUSH_BIND_ADDR"))?;
        let health_addr = e
            .get("BUZZ_PUSH_HEALTH_ADDR")
            .map(String::as_str)
            .unwrap_or("0.0.0.0:8081")
            .parse::<SocketAddr>()
            .map_err(|_| ConfigError::Invalid("BUZZ_PUSH_HEALTH_ADDR"))?;
        Ok(Self {
            bind_addr,
            health_addr,
            max_grant_lifetime_seconds,
            max_installation_lifetime_seconds,
            endpoint_quota_window_seconds,
            endpoint_quota_max_deliveries,
            live_activity_quota_window_seconds,
            live_activity_quota_max_deliveries,
            profile,
            database_url: req(e, "DATABASE_URL")?.to_owned(),
            app_attest_root_cert_path: req(e, "BUZZ_PUSH_APP_ATTEST_ROOT_CERT_PATH")?.into(),
            grant_keys,
            token_keys,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn attestation_environment_is_explicit_and_build_gated() {
        let mut env = base();
        assert_eq!(
            Config::from_map(&env)
                .unwrap()
                .profile
                .app_attest_environment,
            AppAttestEnvironment::Production
        );
        for value in ["", "sandbox", "Production", "unknown"] {
            env.insert("BUZZ_PUSH_APP_ATTEST_ENVIRONMENT".into(), value.into());
            assert!(Config::from_map(&env).is_err());
        }
        env.insert(
            "BUZZ_PUSH_APP_ATTEST_ENVIRONMENT".into(),
            "production".into(),
        );
        assert_eq!(
            Config::from_map(&env)
                .unwrap()
                .profile
                .app_attest_environment,
            AppAttestEnvironment::Production
        );
        env.insert(
            "BUZZ_PUSH_APP_ATTEST_ENVIRONMENT".into(),
            "development".into(),
        );
        #[cfg(feature = "personal-dev-app-attest")]
        assert_eq!(
            Config::from_map(&env)
                .unwrap()
                .profile
                .app_attest_environment,
            AppAttestEnvironment::Development
        );
        #[cfg(not(feature = "personal-dev-app-attest"))]
        assert!(Config::from_map(&env).is_err());
        env.insert(
            "BUZZ_PUSH_APP_ATTEST_ENVIRONMENT".into(),
            "simulator".into(),
        );
        #[cfg(feature = "qa-simulator")]
        assert_eq!(
            Config::from_map(&env)
                .unwrap()
                .profile
                .app_attest_environment,
            AppAttestEnvironment::Simulator
        );
        #[cfg(not(feature = "qa-simulator"))]
        assert!(Config::from_map(&env).is_err());
    }

    #[test]
    fn qa_apns_base_url_needs_the_qa_build() {
        let mut env = base();
        let default = Config::from_map(&env).unwrap().profile;
        assert!(default.apns_base_url().starts_with("https://api."));
        env.insert(
            "BUZZ_PUSH_QA_APNS_BASE_URL".into(),
            "http://127.0.0.1:3463".into(),
        );
        #[cfg(feature = "qa-simulator")]
        assert_eq!(
            Config::from_map(&env).unwrap().profile.apns_base_url(),
            "http://127.0.0.1:3463"
        );
        #[cfg(not(feature = "qa-simulator"))]
        assert!(matches!(
            Config::from_map(&env),
            Err(ConfigError::Invalid("BUZZ_PUSH_QA_APNS_BASE_URL"))
        ));
    }

    fn base() -> HashMap<String, String> {
        HashMap::from([
            (
                "BUZZ_PUSH_GRANT_KEYS".into(),
                format!(
                    "current:{},old:{}",
                    STANDARD.encode([1; 32]),
                    STANDARD.encode([2; 32])
                ),
            ),
            (
                "BUZZ_PUSH_TOKEN_KEYS".into(),
                format!(
                    "current-token:{},old-token:{}",
                    STANDARD.encode([3; 32]),
                    STANDARD.encode([4; 32])
                ),
            ),
            (
                "BUZZ_PUSH_MAX_GRANT_LIFETIME_SECONDS".into(),
                "2592000".into(),
            ),
            (
                "DATABASE_URL".into(),
                "postgres://buzz:test@localhost/buzz".into(), // sadscan:disable np.postgres.1
            ),
            (
                "BUZZ_PUSH_DOGFOOD_APP_ATTEST_APP_ID".into(),
                "TEAM.xyz.block.buzz.dogfood.mobile".into(),
            ),
            (
                "BUZZ_PUSH_APP_ATTEST_ROOT_CERT_PATH".into(),
                "/apple-root.pem".into(),
            ),
            (
                "BUZZ_PUSH_DOGFOOD_APNS_CERT_PATH".into(),
                "/dogfood-identity.pem".into(),
            ),
            (
                "BUZZ_PUSH_DOGFOOD_APNS_TOPIC".into(),
                "xyz.block.buzz.dogfood.mobile".into(),
            ),
            (
                "BUZZ_PUSH_DOGFOOD_APNS_ENVIRONMENT".into(),
                "production".into(),
            ),
            ("BUZZ_PUSH_BIND_ADDR".into(), "127.0.0.1:8080".into()),
            ("BUZZ_PUSH_HEALTH_ADDR".into(), "127.0.0.1:8081".into()),
        ])
    }

    #[test]
    fn dogfood_profile_requires_server_owned_identity_and_certificate() {
        let config = Config::from_map(&base()).unwrap();
        assert_eq!(
            config.profile.apns_cert_path,
            PathBuf::from("/dogfood-identity.pem")
        );
        assert_eq!(config.profile.apns_topic, "xyz.block.buzz.dogfood.mobile");

        for variable in [
            "BUZZ_PUSH_DOGFOOD_APNS_CERT_PATH",
            "BUZZ_PUSH_DOGFOOD_APNS_TOPIC",
            "BUZZ_PUSH_DOGFOOD_APP_ATTEST_APP_ID",
        ] {
            let mut env = base();
            env.remove(variable);
            assert!(
                matches!(Config::from_map(&env), Err(ConfigError::Missing(key)) if key == variable)
            );
        }
    }

    #[test]
    fn startup_needs_no_origin_and_transcript_audiences_stay_registered() {
        assert!(!base().contains_key("BUZZ_PUSH_GATEWAY_ORIGIN"));
        Config::from_map(&base()).unwrap();
        assert_eq!(ENROLL_AUDIENCE, "https://push.buzz.xyz/v1/installations");
        assert_eq!(DELEGATE_AUDIENCE, "https://push.buzz.xyz/v1/delegations");
        assert_eq!(
            ROTATE_ENDPOINT_AUDIENCE,
            "https://push.buzz.xyz/v1/installations/endpoint"
        );
        assert_eq!(
            REVOKE_DELEGATION_AUDIENCE,
            "https://push.buzz.xyz/v1/delegations/revoke"
        );
        assert_eq!(
            REVOKE_INSTALLATION_AUDIENCE,
            "https://push.buzz.xyz/v1/installations/revoke"
        );
    }

    #[test]
    fn live_activity_credentials_are_all_or_none() {
        let keys = [
            (
                "BUZZ_PUSH_DOGFOOD_APNS_AUTH_KEY_PATH",
                "/run/buzz/apns/auth-key.p8",
            ),
            ("BUZZ_PUSH_DOGFOOD_APNS_AUTH_KEY_ID", "ABC123DEFG"),
            ("BUZZ_PUSH_DOGFOOD_APNS_TEAM_ID", "55S37D9HA7"),
        ];
        let mut env = base();
        env.extend(keys.map(|(k, v)| (k.to_owned(), v.to_owned())));
        assert_eq!(
            Config::from_map(&env).unwrap().profile.live_activity,
            Some(LiveActivityCredentials {
                auth_key_path: PathBuf::from("/run/buzz/apns/auth-key.p8"),
                key_id: "ABC123DEFG".into(),
                team_id: "55S37D9HA7".into(),
            })
        );
        for (missing, _) in keys {
            for absent in [None, Some("")] {
                let mut partial = env.clone();
                match absent {
                    None => partial.remove(missing),
                    Some(value) => partial.insert(missing.into(), value.into()),
                };
                assert!(
                    matches!(Config::from_map(&partial), Err(ConfigError::Missing(key)) if key == missing),
                    "{missing}"
                );
            }
        }
        for (key, value) in [
            ("BUZZ_PUSH_DOGFOOD_APNS_AUTH_KEY_ID", "short"),
            ("BUZZ_PUSH_DOGFOOD_APNS_AUTH_KEY_ID", "ABC123DEF!"),
            ("BUZZ_PUSH_DOGFOOD_APNS_TEAM_ID", "55S37D9HA77"),
        ] {
            let mut invalid = env.clone();
            invalid.insert(key.into(), value.into());
            assert!(
                matches!(Config::from_map(&invalid), Err(ConfigError::Invalid(k)) if k == key),
                "{key}={value}"
            );
        }
    }

    #[test]
    fn startup_without_live_activity_credentials_keeps_alert_push() {
        let mut env = base();
        for key in [
            "BUZZ_PUSH_DOGFOOD_APNS_AUTH_KEY_PATH",
            "BUZZ_PUSH_DOGFOOD_APNS_AUTH_KEY_ID",
            "BUZZ_PUSH_DOGFOOD_APNS_TEAM_ID",
        ] {
            env.insert(key.into(), String::new());
        }
        let config = Config::from_map(&env).unwrap();
        assert_eq!(config.profile.live_activity, None);
        assert_eq!(
            config.profile.apns_cert_path,
            PathBuf::from("/dogfood-identity.pem")
        );
        assert!(crate::live_activity::transport_from_config(&config.profile)
            .unwrap()
            .is_none());
    }

    #[test]
    fn live_activity_quota_has_its_own_small_defaults() {
        let config = Config::from_map(&base()).unwrap();
        assert_eq!(
            (
                config.live_activity_quota_window_seconds,
                config.live_activity_quota_max_deliveries
            ),
            (10, 10)
        );
        let mut env = base();
        env.insert(
            "BUZZ_PUSH_LIVE_ACTIVITY_QUOTA_MAX_DELIVERIES".into(),
            "4".into(),
        );
        env.insert("BUZZ_PUSH_ENDPOINT_QUOTA_MAX_DELIVERIES".into(), "7".into());
        let config = Config::from_map(&env).unwrap();
        assert_eq!(config.live_activity_quota_max_deliveries, 4);
        assert_eq!(config.endpoint_quota_max_deliveries, 7);
        for (key, value) in [
            ("BUZZ_PUSH_LIVE_ACTIVITY_QUOTA_WINDOW_SECONDS", "0"),
            ("BUZZ_PUSH_LIVE_ACTIVITY_QUOTA_WINDOW_SECONDS", "86401"),
            ("BUZZ_PUSH_LIVE_ACTIVITY_QUOTA_MAX_DELIVERIES", ""),
            ("BUZZ_PUSH_LIVE_ACTIVITY_QUOTA_MAX_DELIVERIES", "10001"),
        ] {
            let mut env = base();
            env.insert(key.into(), value.into());
            assert!(
                matches!(Config::from_map(&env), Err(ConfigError::Invalid(k)) if k == key),
                "{key}={value}"
            );
        }
    }

    #[test]
    fn keyrings_preserve_current_then_predecessor_order_and_are_independent() {
        let config = Config::from_map(&base()).unwrap();
        assert_eq!(config.grant_keys[0].id, "current");
        assert_eq!(config.grant_keys[1].id, "old");
        assert_eq!(config.token_keys[0].id, "current-token");
        assert_eq!(config.token_keys[1].id, "old-token");
        assert_ne!(config.grant_keys[0].key, config.token_keys[0].key);
    }

    #[test]
    fn malformed_security_configuration_fails_startup() {
        for (key, value) in [
            ("BUZZ_PUSH_DOGFOOD_APP_ATTEST_APP_ID", ""),
            ("BUZZ_PUSH_DOGFOOD_APNS_ENVIRONMENT", "staging"),
            ("BUZZ_PUSH_MAX_GRANT_LIFETIME_SECONDS", "0"),
            ("BUZZ_PUSH_MAX_GRANT_LIFETIME_SECONDS", "31536001"),
            ("BUZZ_PUSH_MAX_GRANT_LIFETIME_SECONDS", "2.592e+06"),
            ("BUZZ_PUSH_MAX_GRANT_LIFETIME_SECONDS", "2592000.5"),
            ("BUZZ_PUSH_MAX_INSTALLATION_LIFETIME_SECONDS", "0"),
        ] {
            let mut env = base();
            env.insert(key.into(), value.into());
            assert!(Config::from_map(&env).is_err(), "accepted {key}={value}");
        }
    }

    // The chart test supplies actual Helm-rendered environment values. Keep this
    // separate from ordinary unit tests, which do not require Helm or fixtures.
    #[test]
    #[ignore = "run deploy/charts/buzz-push-gateway/tests/grant-lifetime.sh"]
    fn helm_rendered_grant_lifetimes() {
        let path = std::env::var("BUZZ_TEST_HELM_ENV_FILE").unwrap();
        let cases: Vec<(String, i64, HashMap<String, String>)> =
            serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap();
        assert_eq!(cases.len(), 9);
        for (label, expected, rendered) in cases {
            let mut env = base();
            env.extend(rendered);
            let config = Config::from_map(&env).unwrap_or_else(|error| panic!("{label}: {error}"));
            assert_eq!(config.max_grant_lifetime_seconds, expected, "{label}");
            assert_eq!(
                env["BUZZ_PUSH_MAX_GRANT_LIFETIME_SECONDS"],
                expected.to_string(),
                "{label} must render decimal integer text"
            );
        }
    }

    #[test]
    fn cross_keyring_id_or_material_reuse_fails_startup() {
        for token_keys in [
            format!("current:{}", STANDARD.encode([9; 32])),
            format!("other:{}", STANDARD.encode([1; 32])),
        ] {
            let mut env = base();
            env.insert("BUZZ_PUSH_TOKEN_KEYS".into(), token_keys);
            assert!(Config::from_map(&env).is_err());
        }
    }

    #[test]
    fn listener_defaults_remain_public_when_addresses_are_absent() {
        let mut env = base();
        env.remove("BUZZ_PUSH_BIND_ADDR");
        env.remove("BUZZ_PUSH_HEALTH_ADDR");

        let config = Config::from_map(&env).unwrap();
        assert_eq!(config.bind_addr, "0.0.0.0:8080".parse().unwrap());
        assert_eq!(config.health_addr, "0.0.0.0:8081".parse().unwrap());
    }

    #[test]
    fn malformed_or_empty_keyrings_fail_startup() {
        for (variable, value) in [
            ("BUZZ_PUSH_GRANT_KEYS", ""),
            ("BUZZ_PUSH_GRANT_KEYS", "missing_separator"),
            ("BUZZ_PUSH_GRANT_KEYS", "id:bad-base64"),
            ("BUZZ_PUSH_TOKEN_KEYS", ""),
            ("BUZZ_PUSH_TOKEN_KEYS", "missing_separator"),
            ("BUZZ_PUSH_TOKEN_KEYS", "id:bad-base64"),
        ] {
            let mut env = base();
            env.insert(variable.into(), value.into());
            assert!(Config::from_map(&env).is_err());
        }
    }
}
