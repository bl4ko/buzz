use super::project_git_exec::{clean_branch, validate_workspace_clone_url};
use super::project_git_file_content::validate_repo_file_path;
use crate::app_state::AppState;
use flate2::{Decompress, FlushDecompress, Status};
use nostr::Keys;
use reqwest::Method;
use serde::Serialize;
use sha1::{Digest, Sha1};
use std::collections::HashMap;
use std::time::Duration;
use tauri::State;

const MAX_FILE_BYTES: usize = 100 * 1024;
const MAX_PACK_BYTES: usize = 64 * 1024 * 1024;
const MAX_OBJECT_BYTES: usize = 16 * 1024 * 1024;
const MAX_DELTA_DEPTH: usize = 128;
const REQUEST_TIMEOUT: Duration = Duration::from_secs(60);

#[derive(Debug, Serialize, PartialEq)]
pub struct OlympusGitFile {
    pub base: String,
    pub content: String,
}

#[tauri::command]
pub async fn read_olympus_git_file(
    clone_url: String,
    branch: String,
    path: String,
    state: State<'_, AppState>,
) -> Result<OlympusGitFile, String> {
    validate_workspace_clone_url(&clone_url, &state)?;
    let parsed = url::Url::parse(&clone_url).map_err(|error| error.to_string())?;
    if parsed.query().is_some()
        || parsed.fragment().is_some()
        || parsed.has_authority() && !parsed.username().is_empty()
    {
        return Err("clone URL must be a plain repository URL".into());
    }
    validate_repo_file_path(&path)?;
    let branch = clean_branch(Some(branch)).ok_or("The branch name is not valid.")?;
    let keys = state.signing_keys()?;
    let repo = clone_url.trim_end_matches('/');

    let refs = fetch(
        &state.http_client,
        &keys,
        Method::GET,
        repo,
        &format!("{repo}/info/refs?service=git-upload-pack"),
        None,
    )
    .await?;
    let base = branch_head(&refs, &branch)?
        .ok_or_else(|| format!("The branch {branch} has no commit."))?;

    let response = fetch(
        &state.http_client,
        &keys,
        Method::POST,
        repo,
        &format!("{repo}/git-upload-pack"),
        Some(upload_pack_request(&base)),
    )
    .await?;
    tauri::async_runtime::spawn_blocking(move || {
        let objects = parse_pack(pack_from_response(&response)?)?;
        let content = file_at(&objects, &base, &path)?;
        Ok(OlympusGitFile { base, content })
    })
    .await
    .map_err(|error| format!("read task failed: {error}"))?
}

async fn fetch(
    client: &reqwest::Client,
    keys: &Keys,
    method: Method,
    repo: &str,
    url: &str,
    body: Option<Vec<u8>>,
) -> Result<Vec<u8>, String> {
    let auth = crate::relay::build_nip98_auth_header_for_keys(keys, &method, repo, &[])?;
    let mut request = client
        .request(method, url)
        .timeout(REQUEST_TIMEOUT)
        .header(reqwest::header::AUTHORIZATION, auth);
    if let Some(body) = body {
        request = request
            .header(
                reqwest::header::CONTENT_TYPE,
                "application/x-git-upload-pack-request",
            )
            .header(
                reqwest::header::ACCEPT,
                "application/x-git-upload-pack-result",
            )
            .body(body);
    }
    let mut response = request
        .send()
        .await
        .map_err(|error| crate::relay::classify_request_error(&error))?;
    let status = response.status();
    if !status.is_success() {
        let text = response.text().await.unwrap_or_default();
        let text = text.trim();
        return Err(if text.is_empty() {
            format!("The git server answered {status}.")
        } else {
            format!("The git server answered {status}: {}", truncate(text, 200))
        });
    }
    let mut bytes = Vec::new();
    while let Some(chunk) = response
        .chunk()
        .await
        .map_err(|error| crate::relay::classify_request_error(&error))?
    {
        if bytes.len() + chunk.len() > MAX_PACK_BYTES {
            return Err("The git server sent too much data.".into());
        }
        bytes.extend_from_slice(&chunk);
    }
    Ok(bytes)
}

fn truncate(text: &str, max: usize) -> &str {
    match text.char_indices().nth(max) {
        Some((index, _)) => &text[..index],
        None => text,
    }
}

fn pkt_line(out: &mut Vec<u8>, line: &str) {
    out.extend_from_slice(format!("{:04x}", line.len() + 4).as_bytes());
    out.extend_from_slice(line.as_bytes());
}

fn upload_pack_request(want: &str) -> Vec<u8> {
    let mut out = Vec::new();
    pkt_line(
        &mut out,
        &format!("want {want} ofs-delta shallow no-progress\n"),
    );
    pkt_line(&mut out, "deepen 1\n");
    out.extend_from_slice(b"0000");
    pkt_line(&mut out, "done\n");
    out
}

fn next_pkt(data: &[u8], pos: &mut usize) -> Result<Option<Vec<u8>>, String> {
    let header = data
        .get(*pos..*pos + 4)
        .ok_or("The git server answer ended early.")?;
    let len = std::str::from_utf8(header)
        .ok()
        .and_then(|text| usize::from_str_radix(text, 16).ok())
        .ok_or("The git server answer is not valid.")?;
    if len < 4 {
        *pos += 4;
        return Ok(None);
    }
    let line = data
        .get(*pos + 4..*pos + len)
        .ok_or("The git server answer ended early.")?
        .to_vec();
    *pos += len;
    Ok(Some(line))
}

fn branch_head(advertisement: &[u8], branch: &str) -> Result<Option<String>, String> {
    let wanted = format!("refs/heads/{branch}");
    let mut pos = 0;
    while pos < advertisement.len() {
        let Some(line) = next_pkt(advertisement, &mut pos)? else {
            continue;
        };
        let line = line.split(|byte| *byte == 0).next().unwrap_or_default();
        let line = String::from_utf8_lossy(line);
        let line = line.trim_end();
        if let Some(message) = line.strip_prefix("ERR ") {
            return Err(format!("The git server refused: {message}"));
        }
        if let Some((oid, name)) = line.split_once(' ') {
            if name == wanted {
                if oid.len() != 40 || !oid.bytes().all(|b| b.is_ascii_hexdigit()) {
                    return Err("Only SHA-1 repositories are supported.".into());
                }
                return Ok(Some(oid.to_ascii_lowercase()));
            }
        }
    }
    Ok(None)
}

fn pack_from_response(data: &[u8]) -> Result<&[u8], String> {
    let mut pos = 0;
    loop {
        if data.get(pos..pos + 4) == Some(b"PACK") {
            return Ok(&data[pos..]);
        }
        if pos >= data.len() {
            return Err("The git server sent no pack.".into());
        }
        if let Some(line) = next_pkt(data, &mut pos)? {
            if let Some(message) = line.strip_prefix(b"ERR ") {
                return Err(format!(
                    "The git server refused: {}",
                    String::from_utf8_lossy(message).trim_end()
                ));
            }
        }
    }
}

#[derive(Clone, Copy, PartialEq, Debug)]
enum Kind {
    Commit = 1,
    Tree = 2,
    Blob = 3,
    Tag = 4,
}

impl Kind {
    fn from_type(value: u8) -> Option<Self> {
        match value {
            1 => Some(Self::Commit),
            2 => Some(Self::Tree),
            3 => Some(Self::Blob),
            4 => Some(Self::Tag),
            _ => None,
        }
    }

    fn name(self) -> &'static str {
        match self {
            Self::Commit => "commit",
            Self::Tree => "tree",
            Self::Blob => "blob",
            Self::Tag => "tag",
        }
    }
}

enum Entry {
    Full(Kind, Vec<u8>),
    OfsDelta(usize, Vec<u8>),
    RefDelta([u8; 20], Vec<u8>),
}

type Objects = HashMap<[u8; 20], (Kind, Vec<u8>)>;

fn byte(pack: &[u8], pos: &mut usize) -> Result<u8, String> {
    let value = *pack.get(*pos).ok_or("The pack ended early.")?;
    *pos += 1;
    Ok(value)
}

fn inflate(pack: &[u8], pos: &mut usize, size: usize) -> Result<Vec<u8>, String> {
    if size > MAX_OBJECT_BYTES {
        return Err("A git object is too large.".into());
    }
    let mut out = Vec::with_capacity(size);
    let mut inflater = Decompress::new(true);
    let input = pack.get(*pos..).ok_or("The pack ended early.")?;
    loop {
        let (read, written) = (inflater.total_in(), inflater.total_out());
        if out.len() == out.capacity() {
            out.reserve(64);
        }
        let status = inflater
            .decompress_vec(&input[read as usize..], &mut out, FlushDecompress::None)
            .map_err(|_| "The pack is not valid.".to_string())?;
        if out.len() > size {
            return Err("The pack is not valid.".into());
        }
        if status == Status::StreamEnd {
            break;
        }
        if inflater.total_in() == read && inflater.total_out() == written {
            return Err("The pack ended early.".into());
        }
    }
    if out.len() != size {
        return Err("The pack is not valid.".into());
    }
    *pos += inflater.total_in() as usize;
    Ok(out)
}

fn object_id(kind: Kind, data: &[u8]) -> [u8; 20] {
    let mut hasher = Sha1::new();
    hasher.update(format!("{} {}\0", kind.name(), data.len()).as_bytes());
    hasher.update(data);
    hasher.finalize().into()
}

fn delta_size(delta: &[u8], pos: &mut usize) -> Result<usize, String> {
    let mut size = 0usize;
    let mut shift = 0;
    loop {
        let value = byte(delta, pos)?;
        size |= usize::from(value & 0x7f) << shift;
        shift += 7;
        if value & 0x80 == 0 || shift > 56 {
            return Ok(size);
        }
    }
}

fn apply_delta(base: &[u8], delta: &[u8]) -> Result<Vec<u8>, String> {
    let bad = || "A git delta is not valid.".to_string();
    let mut pos = 0;
    if delta_size(delta, &mut pos)? != base.len() {
        return Err(bad());
    }
    let size = delta_size(delta, &mut pos)?;
    if size > MAX_OBJECT_BYTES {
        return Err("A git object is too large.".into());
    }
    let mut out = Vec::with_capacity(size);
    while pos < delta.len() {
        let op = byte(delta, &mut pos)?;
        if op & 0x80 != 0 {
            let mut offset = 0usize;
            let mut len = 0usize;
            for bit in 0..4 {
                if op & (1 << bit) != 0 {
                    offset |= usize::from(byte(delta, &mut pos)?) << (8 * bit);
                }
            }
            for bit in 0..3 {
                if op & (0x10 << bit) != 0 {
                    len |= usize::from(byte(delta, &mut pos)?) << (8 * bit);
                }
            }
            if len == 0 {
                len = 0x10000;
            }
            out.extend_from_slice(base.get(offset..offset + len).ok_or_else(bad)?);
        } else if op != 0 {
            let len = usize::from(op);
            out.extend_from_slice(delta.get(pos..pos + len).ok_or_else(bad)?);
            pos += len;
        } else {
            return Err(bad());
        }
        if out.len() > size {
            return Err(bad());
        }
    }
    if out.len() != size {
        return Err(bad());
    }
    Ok(out)
}

fn parse_pack(pack: &[u8]) -> Result<Objects, String> {
    if pack.len() < 12 || &pack[..4] != b"PACK" || !matches!(pack[7], 2 | 3) || pack[4..7] != [0; 3]
    {
        return Err("The git server sent no valid pack.".into());
    }
    let count = u32::from_be_bytes([pack[8], pack[9], pack[10], pack[11]]) as usize;
    let mut pos = 12;
    let mut entries = Vec::with_capacity(count.min(100_000));
    let mut by_offset = HashMap::new();
    for index in 0..count {
        let offset = pos;
        let mut value = byte(pack, &mut pos)?;
        let kind = (value >> 4) & 7;
        let mut size = usize::from(value & 0x0f);
        let mut shift = 4;
        while value & 0x80 != 0 {
            value = byte(pack, &mut pos)?;
            if shift > 56 {
                return Err("The pack is not valid.".into());
            }
            size |= usize::from(value & 0x7f) << shift;
            shift += 7;
        }
        let entry = match kind {
            6 => {
                value = byte(pack, &mut pos)?;
                let mut distance = usize::from(value & 0x7f);
                while value & 0x80 != 0 {
                    value = byte(pack, &mut pos)?;
                    distance = distance
                        .checked_add(1)
                        .and_then(|d| d.checked_mul(128))
                        .ok_or("The pack is not valid.")?
                        | usize::from(value & 0x7f);
                }
                let base = offset
                    .checked_sub(distance)
                    .ok_or("The pack is not valid.")?;
                Entry::OfsDelta(base, inflate(pack, &mut pos, size)?)
            }
            7 => {
                let id: [u8; 20] = pack
                    .get(pos..pos + 20)
                    .ok_or("The pack ended early.")?
                    .try_into()
                    .map_err(|_| "The pack is not valid.")?;
                pos += 20;
                Entry::RefDelta(id, inflate(pack, &mut pos, size)?)
            }
            kind => {
                let kind = Kind::from_type(kind).ok_or("The pack is not valid.")?;
                Entry::Full(kind, inflate(pack, &mut pos, size)?)
            }
        };
        by_offset.insert(offset, index);
        entries.push(entry);
    }

    let mut resolved: Vec<Option<(Kind, Vec<u8>)>> = vec![None; entries.len()];
    let mut objects = Objects::new();
    loop {
        let mut progress = false;
        for index in 0..entries.len() {
            if resolved[index].is_some() {
                continue;
            }
            if let Some((kind, data)) =
                resolve(index, &entries, &by_offset, &mut resolved, &objects, 0)?
            {
                objects.insert(object_id(kind, &data), (kind, data));
                progress = true;
            }
        }
        if resolved.iter().all(Option::is_some) {
            return Ok(objects);
        }
        if !progress {
            return Err("The pack refers to objects that it does not have.".into());
        }
    }
}

fn resolve(
    index: usize,
    entries: &[Entry],
    by_offset: &HashMap<usize, usize>,
    resolved: &mut [Option<(Kind, Vec<u8>)>],
    objects: &Objects,
    depth: usize,
) -> Result<Option<(Kind, Vec<u8>)>, String> {
    if let Some(done) = &resolved[index] {
        return Ok(Some(done.clone()));
    }
    if depth > MAX_DELTA_DEPTH {
        return Err("A git delta chain is too long.".into());
    }
    let result = match &entries[index] {
        Entry::Full(kind, data) => Some((*kind, data.clone())),
        Entry::OfsDelta(base, delta) => {
            let base = *by_offset.get(base).ok_or("The pack is not valid.")?;
            resolve(base, entries, by_offset, resolved, objects, depth + 1)?
                .map(|(kind, data)| apply_delta(&data, delta).map(|data| (kind, data)))
                .transpose()?
        }
        Entry::RefDelta(id, delta) => objects
            .get(id)
            .map(|(kind, data)| apply_delta(data, delta).map(|data| (*kind, data)))
            .transpose()?,
    };
    resolved[index].clone_from(&result);
    Ok(result)
}

fn hex_id(text: &str) -> Option<[u8; 20]> {
    hex::decode(text).ok()?.try_into().ok()
}

fn file_at(objects: &Objects, commit: &str, path: &str) -> Result<String, String> {
    let short = &commit[..7];
    let missing = || format!("The git server did not send commit {short}.");
    let (kind, data) = objects
        .get(&hex_id(commit).ok_or_else(missing)?)
        .ok_or_else(missing)?;
    if *kind != Kind::Commit {
        return Err(missing());
    }
    let tree = std::str::from_utf8(data)
        .ok()
        .and_then(|text| text.lines().next())
        .and_then(|line| line.strip_prefix("tree "))
        .and_then(hex_id)
        .ok_or("The commit is not valid.")?;

    let parts: Vec<&str> = path.split('/').collect();
    let mut current = tree;
    for (index, name) in parts.iter().enumerate() {
        let (kind, data) = objects
            .get(&current)
            .ok_or("The git server did not send the whole tree.")?;
        if *kind != Kind::Tree {
            return Err(format!("{path} is missing at {short}."));
        }
        let (mode, id) =
            tree_entry(data, name)?.ok_or_else(|| format!("{path} is missing at {short}."))?;
        let last = index + 1 == parts.len();
        match (last, mode.as_str()) {
            (false, "40000") => current = id,
            (true, "100644" | "100755") => {
                let (_, blob) = objects
                    .get(&id)
                    .ok_or("The git server did not send the file.")?;
                if blob.len() > MAX_FILE_BYTES {
                    return Err(format!("{path} is larger than 100 KiB at {short}."));
                }
                if blob.contains(&0) {
                    return Err(format!("{path} is binary at {short}."));
                }
                return String::from_utf8(blob.clone())
                    .map_err(|_| format!("{path} is not UTF-8 text at {short}."));
            }
            _ => return Err(format!("{path} is not a regular file at {short}.")),
        }
    }
    Err(format!("{path} is missing at {short}."))
}

fn tree_entry(tree: &[u8], wanted: &str) -> Result<Option<(String, [u8; 20])>, String> {
    let bad = || "A git tree is not valid.".to_string();
    let mut pos = 0;
    while pos < tree.len() {
        let space = tree[pos..]
            .iter()
            .position(|b| *b == b' ')
            .ok_or_else(bad)?
            + pos;
        let nul = tree[space..].iter().position(|b| *b == 0).ok_or_else(bad)? + space;
        let id: [u8; 20] = tree
            .get(nul + 1..nul + 21)
            .ok_or_else(bad)?
            .try_into()
            .map_err(|_| bad())?;
        if &tree[space + 1..nul] == wanted.as_bytes() {
            return Ok(Some((
                String::from_utf8_lossy(&tree[pos..space]).into_owned(),
                id,
            )));
        }
        pos = nul + 21;
    }
    Ok(None)
}

#[cfg(test)]
#[path = "olympus_git_file_tests.rs"]
mod tests;
