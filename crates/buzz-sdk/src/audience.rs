//! Explicit presentation intent for channel messages. This is not an ACL.

/// Who a message is intended to address, independently of its recipients.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MessageAudience {
    /// Agent-to-agent coordination, still readable by channel members.
    Agents,
    /// Ordinary human-facing conversation (not a mass notification).
    Everyone,
}

impl MessageAudience {
    /// Canonical signed wire value.
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Agents => "agents",
            Self::Everyone => "everyone",
        }
    }

    /// Add the audience declaration to a newly constructed message builder.
    /// Call once, before signing; do not use to reclassify existing events.
    pub fn apply(
        self,
        builder: nostr::EventBuilder,
    ) -> Result<nostr::EventBuilder, crate::SdkError> {
        let tag = nostr::Tag::parse(["audience", self.as_str()])
            .map_err(|e| crate::SdkError::InvalidTag(e.to_string()))?;
        Ok(builder.tag(tag))
    }
}

impl std::str::FromStr for MessageAudience {
    type Err = String;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        match value {
            "agents" => Ok(Self::Agents),
            "everyone" => Ok(Self::Everyone),
            _ => Err("audience must be agents or everyone".into()),
        }
    }
}

/// Only a single well-formed declaration on supported message kinds opts into coordination.
/// Unknown/ambiguous tags fail open for visibility, never hide legacy messages.
pub fn is_agent_coordination(kind: u16, tags: &[Vec<String>]) -> bool {
    if !matches!(kind, 9 | 45001 | 45003) {
        return false;
    }
    let mut declarations = tags
        .iter()
        .filter(|tag| tag.first().is_some_and(|name| name == "audience"));
    let Some(tag) = declarations.next() else {
        return false;
    };
    declarations.next().is_none() && tag.len() == 2 && tag[1] == "agents"
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn audience_survives_signing_without_changing_message_routing() {
        let keys = nostr::Keys::generate();
        let channel = uuid::Uuid::new_v4();
        let parent = nostr::EventId::all_zeros();
        let thread = crate::ThreadRef {
            root_event_id: parent,
            parent_event_id: parent,
        };
        for audience in [MessageAudience::Agents, MessageAudience::Everyone] {
            let builder =
                crate::build_message(channel, "hello", Some(&thread), &[], false, &[], &[])
                    .unwrap();
            let event = audience
                .apply(builder)
                .unwrap()
                .sign_with_keys(&keys)
                .unwrap();
            event.verify().unwrap();
            let tags: Vec<_> = event.tags.iter().map(|t| t.as_slice()).collect();
            assert_eq!(tags.iter().filter(|t| t[0] == "audience").count(), 1);
            assert!(tags
                .iter()
                .any(|t| t[0] == "audience" && t[1] == audience.as_str()));
            assert!(tags
                .iter()
                .any(|t| t[0] == "h" && t[1] == channel.to_string()));
            assert!(tags.iter().any(|t| t[0] == "e" && t[3] == "reply"));
            assert_eq!(event.kind.as_u16(), 9);
        }
        assert!("broadcast".parse::<MessageAudience>().is_err());
    }
}
