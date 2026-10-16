use super::*;

pub(crate) const NOW: i64 = 1_760_000_000;
pub(crate) const INSTALLATION_EXPIRES_AT: i64 = NOW + 86_400;
pub(crate) const UPDATE_RETENTION: i64 = 12 * 3600;

pub(crate) fn sealed(byte: u8) -> SealedToken {
    SealedToken {
        ciphertext: vec![byte; 8],
        fingerprint: [byte; 32],
    }
}

pub(crate) async fn seed(store: &dyn AuthorityStore) -> Uuid {
    let id = Uuid::new_v4();
    let unique = *id.as_bytes();
    store
        .create_installation(
            NewInstallation {
                id,
                app_attest_key_id: unique.to_vec(),
                app_attest_public_key: vec![2; 65],
                assertion_counter: 0,
                profile: AppProfile::BuzzIosDogfood,
                token_ciphertext: vec![3],
                token_fingerprint: [unique, unique].concat().try_into().unwrap(),
                endpoint_epoch: 1,
                expires_at: INSTALLATION_EXPIRES_AT,
            },
            NOW,
        )
        .await
        .unwrap();
    id
}

pub(crate) async fn registration_replaces_origins(store: &dyn AuthorityStore) {
    let id = seed(store).await;
    let (a, b, c) = ([0xa; 32], [0xb; 32], [0xc; 32]);
    assert_eq!(store.live_activity_target(id, a, NOW).await, Ok(None));
    store
        .replace_live_activity_registration(id, Some(sealed(1)), vec![a, b], NOW)
        .await
        .unwrap();
    store
        .set_live_activity_update_token(id, a, Some(sealed(2)), NOW)
        .await
        .unwrap();
    store
        .record_live_activity_start(id, b, NOW + 1)
        .await
        .unwrap();
    assert_eq!(
        store.live_activity_target(id, a, NOW).await,
        Ok(Some(LiveActivityTarget {
            start_ciphertext: sealed(1).ciphertext,
            update_ciphertext: Some(sealed(2).ciphertext),
            started_at: None,
        }))
    );
    assert_eq!(
        store.live_activity_target(id, b, NOW + 1).await,
        Ok(Some(LiveActivityTarget {
            start_ciphertext: sealed(1).ciphertext,
            update_ciphertext: None,
            started_at: Some(NOW + 1),
        }))
    );
    assert_eq!(store.live_activity_target(id, c, NOW).await, Ok(None));

    store
        .replace_live_activity_registration(id, Some(sealed(3)), vec![b, c], NOW + 2)
        .await
        .unwrap();
    assert_eq!(store.live_activity_target(id, a, NOW + 2).await, Ok(None));
    assert_eq!(
        store.live_activity_target(id, b, NOW + 2).await,
        Ok(Some(LiveActivityTarget {
            start_ciphertext: sealed(3).ciphertext,
            update_ciphertext: None,
            started_at: Some(NOW + 1),
        }))
    );
    store
        .replace_live_activity_registration(id, Some(sealed(3)), vec![b], NOW + 3)
        .await
        .unwrap();
    assert_eq!(store.live_activity_target(id, c, NOW + 3).await, Ok(None));

    store
        .replace_live_activity_registration(id, Some(sealed(3)), vec![a], NOW + 4)
        .await
        .unwrap();
    assert_eq!(
        store.live_activity_target(id, a, NOW + 4).await,
        Ok(Some(LiveActivityTarget {
            start_ciphertext: sealed(3).ciphertext,
            update_ciphertext: None,
            started_at: None,
        })),
        "a re-added origin starts without its old update token"
    );

    for (start, origins) in [(None, vec![a]), (Some(sealed(4)), vec![])] {
        store
            .replace_live_activity_registration(id, Some(sealed(5)), vec![a], NOW + 5)
            .await
            .unwrap();
        store
            .set_live_activity_update_token(id, a, Some(sealed(6)), NOW + 5)
            .await
            .unwrap();
        store
            .replace_live_activity_registration(id, start, origins, NOW + 6)
            .await
            .unwrap();
        assert_eq!(store.live_activity_target(id, a, NOW + 6).await, Ok(None));
    }

    assert_eq!(
        store
            .replace_live_activity_registration(id, Some(sealed(1)), vec![a, a], NOW)
            .await,
        Err(AuthorityError::Rejected)
    );
    assert_eq!(
        store
            .replace_live_activity_registration(
                id,
                Some(sealed(1)),
                (0..17u8).map(|i| [i; 32]).collect(),
                NOW,
            )
            .await,
        Err(AuthorityError::Rejected)
    );
    assert_eq!(
        store
            .replace_live_activity_registration(Uuid::new_v4(), Some(sealed(1)), vec![a], NOW)
            .await,
        Err(AuthorityError::Rejected)
    );
    assert_eq!(
        store
            .replace_live_activity_registration(
                id,
                Some(sealed(1)),
                vec![a],
                INSTALLATION_EXPIRES_AT + 1
            )
            .await,
        Err(AuthorityError::Rejected)
    );
}

pub(crate) async fn update_token_needs_registered_origin(store: &dyn AuthorityStore) {
    let id = seed(store).await;
    let (a, b) = ([0xa; 32], [0xb; 32]);
    assert_eq!(
        store
            .set_live_activity_update_token(id, a, Some(sealed(2)), NOW)
            .await,
        Err(AuthorityError::NotFound)
    );
    assert_eq!(
        store.record_live_activity_start(id, a, NOW).await,
        Err(AuthorityError::NotFound)
    );
    store
        .replace_live_activity_registration(id, Some(sealed(1)), vec![a], NOW)
        .await
        .unwrap();
    assert_eq!(
        store
            .set_live_activity_update_token(id, b, Some(sealed(2)), NOW)
            .await,
        Err(AuthorityError::NotFound)
    );
    store.record_live_activity_start(id, a, NOW).await.unwrap();
    store
        .set_live_activity_update_token(id, a, Some(sealed(2)), NOW + 10)
        .await
        .unwrap();
    assert_eq!(
        store.live_activity_target(id, a, NOW + 10).await,
        Ok(Some(LiveActivityTarget {
            start_ciphertext: sealed(1).ciphertext,
            update_ciphertext: Some(sealed(2).ciphertext),
            started_at: Some(NOW),
        }))
    );
    store
        .record_live_activity_start(id, a, NOW + 20)
        .await
        .unwrap();
    assert_eq!(
        store.live_activity_target(id, a, NOW + 20).await,
        Ok(Some(LiveActivityTarget {
            start_ciphertext: sealed(1).ciphertext,
            update_ciphertext: None,
            started_at: Some(NOW + 20),
        })),
        "a new start clears the old update token"
    );
    store
        .set_live_activity_update_token(id, a, Some(sealed(3)), NOW + 30)
        .await
        .unwrap();
    store
        .set_live_activity_update_token(id, a, None, NOW + 40)
        .await
        .unwrap();
    assert_eq!(
        store.live_activity_target(id, a, NOW + 40).await,
        Ok(Some(LiveActivityTarget {
            start_ciphertext: sealed(1).ciphertext,
            update_ciphertext: None,
            started_at: None,
        }))
    );
    store
        .set_live_activity_update_token(id, a, Some(sealed(3)), NOW + 50)
        .await
        .unwrap();
    store.clear_live_activity(id, a, NOW + 60).await.unwrap();
    store.clear_live_activity(id, a, NOW + 61).await.unwrap();
    assert_eq!(
        store.live_activity_target(id, a, NOW + 61).await,
        Ok(Some(LiveActivityTarget {
            start_ciphertext: sealed(1).ciphertext,
            update_ciphertext: None,
            started_at: None,
        }))
    );
}

pub(crate) async fn revoke_installation_drops_live_activity_rows(store: &dyn AuthorityStore) {
    let id = seed(store).await;
    let a = [0xa; 32];
    store
        .replace_live_activity_registration(id, Some(sealed(1)), vec![a], NOW)
        .await
        .unwrap();
    store
        .set_live_activity_update_token(id, a, Some(sealed(2)), NOW)
        .await
        .unwrap();
    store.revoke_installation(id, 1, 2).await.unwrap();
    assert_eq!(store.live_activity_target(id, a, NOW).await, Ok(None));
    assert_eq!(
        store
            .replace_live_activity_registration(id, Some(sealed(1)), vec![a], NOW)
            .await,
        Err(AuthorityError::Rejected)
    );
    store.revoke_installation(id, 1, 2).await.unwrap();
}

pub(crate) async fn reaper_drops_stale_update_rows(store: &dyn AuthorityStore) {
    let id = seed(store).await;
    let (a, b) = ([0xa; 32], [0xb; 32]);
    store
        .replace_live_activity_registration(id, Some(sealed(1)), vec![a, b], NOW)
        .await
        .unwrap();
    store
        .set_live_activity_update_token(id, a, Some(sealed(2)), NOW)
        .await
        .unwrap();
    store
        .set_live_activity_update_token(id, b, Some(sealed(3)), NOW + 100)
        .await
        .unwrap();
    store.reap_expired(NOW + UPDATE_RETENTION).await.unwrap();
    assert_eq!(
        store
            .live_activity_target(id, a, NOW + UPDATE_RETENTION)
            .await
            .unwrap()
            .unwrap()
            .update_ciphertext,
        Some(sealed(2).ciphertext)
    );
    store
        .reap_expired(NOW + UPDATE_RETENTION + 1)
        .await
        .unwrap();
    let target = |origin| store.live_activity_target(id, origin, NOW + UPDATE_RETENTION + 1);
    assert_eq!(target(a).await.unwrap().unwrap().update_ciphertext, None);
    assert_eq!(
        target(b).await.unwrap().unwrap().update_ciphertext,
        Some(sealed(3).ciphertext)
    );
    store
        .reap_expired(INSTALLATION_EXPIRES_AT + 1)
        .await
        .unwrap();
    assert_eq!(
        store
            .live_activity_target(id, b, INSTALLATION_EXPIRES_AT + 1)
            .await,
        Ok(None)
    );
}
