use super::tests::record_with;
use super::*;

#[test]
fn bundled_goose_preserves_external_goose_and_default() {
    let bundled = known_acp_runtime("goose-acp").unwrap();
    assert_eq!(bundled.id, "goose-bundled");
    assert_eq!(bundled.label, "Goose (bundled)");
    assert_eq!(bundled.underlying_cli, None);
    assert_eq!(bundled.mcp_command, None);
    assert_eq!(bundled.model_env_var, Some("GOOSE_MODEL"));
    assert_eq!(bundled.provider_env_var, Some("GOOSE_PROVIDER"));
    assert!(bundled.cli_install_commands.is_empty());
    assert_eq!(
        normalize_agent_args("goose-acp", vec!["acp".into()]),
        Vec::<String>::new()
    );
    assert_eq!(normalize_agent_args("goose", vec![]), vec!["acp"]);
    assert_eq!(known_acp_runtime("goose").unwrap().commands, &["goose"]);
    assert_eq!(default_agent_command(), "buzz-agent");

    let mut record = record_with(Some("goose-bundled"), None, None);
    assert_eq!(record_agent_command(&record, &[]), "goose-acp");
    let default_env = crate::managed_agents::readiness::resolve_effective_agent_env(
        &record,
        &[],
        Some(bundled),
        &Default::default(),
    );
    for (key, value) in bundled.configuration_defaults() {
        assert_eq!(default_env.env.get(&key), Some(&value));
    }
    assert!(known_acp_runtime("goose")
        .unwrap()
        .configuration_defaults()
        .is_empty());
    record.provider = Some("anthropic".into());
    record.model = Some("explicit-model".into());
    record
        .env_vars
        .insert("ANTHROPIC_API_KEY".into(), "test-key".into());
    let env = crate::managed_agents::readiness::resolve_effective_agent_env(
        &record,
        &[],
        Some(bundled),
        &Default::default(),
    );
    assert_eq!(
        env.env.get("GOOSE_PROVIDER").map(String::as_str),
        Some("anthropic")
    );
    assert_eq!(
        env.env.get("GOOSE_MODEL").map(String::as_str),
        Some("explicit-model")
    );
    assert!(crate::managed_agents::readiness::agent_readiness(&env).is_ready());
    record
        .env_vars
        .insert("GOOSE_MODEL".into(), "env-model".into());
    let env = crate::managed_agents::readiness::resolve_effective_agent_env(
        &record,
        &[],
        Some(bundled),
        &Default::default(),
    );
    assert_eq!(
        env.env.get("GOOSE_MODEL").map(String::as_str),
        Some("env-model")
    );
}

#[test]
fn bundled_goose_display_defaults_match_launch_precedence() {
    use crate::managed_agents::config_bridge::{reader::read_config_surface, InheritedConfigTiers};
    let runtime = known_acp_runtime("goose-bundled").unwrap();
    let mut record = record_with(Some("goose-bundled"), None, None);
    let tiers = InheritedConfigTiers::default();
    let surface = read_config_surface(&record, Some(runtime), None, &tiers, None);
    let defaults = runtime.configuration_defaults();
    if let Some(model) = defaults.get("GOOSE_MODEL") {
        assert_eq!(
            surface.normalized.model.unwrap().value.as_ref(),
            Some(model)
        );
    }
    record.provider = Some("anthropic".into());
    record.model = Some("chosen-model".into());
    let surface = read_config_surface(&record, Some(runtime), None, &tiers, None);
    assert_eq!(
        surface.normalized.model.unwrap().value.as_deref(),
        Some("chosen-model")
    );
    assert_eq!(
        surface.normalized.provider.unwrap().value.as_deref(),
        Some("anthropic")
    );
    record.model = None;
    record.provider = None;
    let tiers = InheritedConfigTiers {
        persona_model: Some("persona-model".into()),
        persona_provider: Some("openai".into()),
        ..Default::default()
    };
    let surface = read_config_surface(&record, Some(runtime), None, &tiers, None);
    assert_eq!(
        surface.normalized.model.unwrap().value.as_deref(),
        Some("persona-model")
    );
    assert_eq!(
        surface.normalized.provider.unwrap().value.as_deref(),
        Some("openai")
    );
}
