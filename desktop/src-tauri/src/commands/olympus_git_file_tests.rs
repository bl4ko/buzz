use super::*;
use std::io::Write;
use std::path::Path;
use std::process::{Command, Stdio};

fn git(dir: &Path, args: &[&str], input: Option<&[u8]>) -> Vec<u8> {
    let mut child = Command::new("git")
        .args(args)
        .current_dir(dir)
        .env("GIT_CONFIG_GLOBAL", "/dev/null")
        .env("GIT_CONFIG_NOSYSTEM", "1")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .spawn()
        .expect("spawn git");
    let mut stdin = child.stdin.take().expect("stdin");
    if let Some(input) = input {
        stdin.write_all(input).expect("write stdin");
    }
    drop(stdin);
    let output = child.wait_with_output().expect("wait git");
    assert!(output.status.success(), "git {args:?} failed");
    output.stdout
}

fn text(lines: usize, tail: &str) -> String {
    let mut out = String::new();
    for line in 0..lines {
        out.push_str(&format!("Rule {line}: keep answers short and exact.\n"));
    }
    out.push_str(tail);
    out
}

fn fixture() -> (tempfile::TempDir, String) {
    let temp = tempfile::tempdir().expect("tempdir");
    let dir = temp.path();
    git(dir, &["init", "-q", "-b", "main"], None);
    std::fs::create_dir_all(dir.join("dev/agents")).expect("mkdir");
    for round in 0..4 {
        std::fs::write(
            dir.join("dev/agents/testbed.md"),
            text(300, &format!("round {round}\n")),
        )
        .expect("write");
        std::fs::write(
            dir.join("dev/agents/other.md"),
            text(300, &format!("other {round}\n")),
        )
        .expect("write");
        git(dir, &["add", "-A"], None);
        git(
            dir,
            &[
                "-c",
                "user.name=t",
                "-c",
                "user.email=t@example.com",
                "commit",
                "-qm",
                &format!("round {round}"),
            ],
            None,
        );
    }
    std::fs::write(dir.join("bin.dat"), b"a\0b").expect("write");
    std::os::unix::fs::symlink("dev/agents/testbed.md", dir.join("link.md")).expect("symlink");
    git(dir, &["add", "-A"], None);
    git(
        dir,
        &[
            "-c",
            "user.name=t",
            "-c",
            "user.email=t@example.com",
            "commit",
            "-qm",
            "extra",
        ],
        None,
    );
    git(dir, &["repack", "-adfq", "--depth=50", "--window=50"], None);
    let head = String::from_utf8(git(dir, &["rev-parse", "HEAD"], None))
        .expect("utf8")
        .trim()
        .to_string();
    (temp, head)
}

fn served_pack(dir: &Path, request: &[u8]) -> Objects {
    let response = git(dir, &["upload-pack", "--stateless-rpc", "."], Some(request));
    parse_pack(pack_from_response(&response).expect("pack")).expect("parse")
}

#[test]
fn reads_the_file_at_the_branch_head_like_the_relay_serves_it() {
    let (temp, head) = fixture();
    let dir = temp.path();
    let mut advertisement = Vec::new();
    pkt_line(&mut advertisement, "# service=git-upload-pack\n");
    advertisement.extend_from_slice(b"0000");
    advertisement.extend(git(
        dir,
        &["upload-pack", "--stateless-rpc", "--advertise-refs", "."],
        None,
    ));
    assert_eq!(
        branch_head(&advertisement, "main").expect("refs"),
        Some(head.clone())
    );
    assert_eq!(branch_head(&advertisement, "other").expect("refs"), None);

    let objects = served_pack(dir, &upload_pack_request(&head));
    assert_eq!(
        file_at(&objects, &head, "dev/agents/testbed.md").expect("file"),
        text(300, "round 3\n")
    );
    let missing = file_at(&objects, &head, "dev/agents/nope.md").unwrap_err();
    assert!(missing.contains("is missing"), "{missing}");
    for path in ["link.md", "dev/agents", "dev"] {
        let error = file_at(&objects, &head, path).unwrap_err();
        assert!(error.contains("not a regular file"), "{path}: {error}");
    }
    let error = file_at(&objects, &head, "bin.dat").unwrap_err();
    assert!(error.contains("binary"), "{error}");
    let error = file_at(&objects, &head, "dev/agents/testbed.md/x").unwrap_err();
    assert!(error.contains("not a regular file"), "{error}");
}

#[test]
fn resolves_offset_and_reference_deltas_for_every_object() {
    let (temp, _) = fixture();
    let dir = temp.path();
    let all = String::from_utf8(git(
        dir,
        &[
            "cat-file",
            "--batch-all-objects",
            "--batch-check=%(objectname)",
        ],
        None,
    ))
    .expect("utf8");
    let ids: Vec<&str> = all.lines().collect();
    let list = git(dir, &["rev-list", "--objects", "--all"], None);
    for flags in [&["--delta-base-offset"][..], &[][..]] {
        let mut args = vec!["pack-objects", "--stdout", "-q", "--depth=50"];
        args.extend_from_slice(flags);
        let pack = git(dir, &args, Some(&list));
        let objects = parse_pack(&pack).expect("parse");
        assert_eq!(objects.len(), ids.len());
        for id in &ids {
            assert!(objects.contains_key(&hex_id(id).expect("id")), "{id}");
        }
    }
}

#[test]
fn rejects_broken_answers() {
    let (temp, head) = fixture();
    let response = git(
        temp.path(),
        &["upload-pack", "--stateless-rpc", "."],
        Some(&upload_pack_request(&head)),
    );
    let pack = pack_from_response(&response).expect("pack");
    assert!(parse_pack(&pack[..pack.len() / 2]).is_err());
    assert!(parse_pack(b"PACK\0\0\0\x09\0\0\0\0").is_err());

    let mut refused = Vec::new();
    pkt_line(&mut refused, "ERR access denied\n");
    assert_eq!(
        pack_from_response(&refused).unwrap_err(),
        "The git server refused: access denied"
    );
    assert!(branch_head(&refused, "main").is_err());
    assert!(pack_from_response(b"0008NAK\n").is_err());
    assert!(pack_from_response(b"zz").is_err());

    let mut sha256 = Vec::new();
    pkt_line(
        &mut sha256,
        &format!("{} refs/heads/main\n", "a".repeat(64)),
    );
    assert!(branch_head(&sha256, "main").is_err());

    assert!(apply_delta(b"abc", &[3, 1, 0x91, 5, 1]).is_err());
    assert!(apply_delta(b"abc", &[4, 1, 0x91, 0, 1]).is_err());
    assert_eq!(
        apply_delta(b"abc", &[3, 4, 0x91, 1, 2, 2, b'x', b'y']).expect("delta"),
        b"bcxy"
    );
}
