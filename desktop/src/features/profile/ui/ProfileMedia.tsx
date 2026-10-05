import { useMutation, useQueryClient } from "@tanstack/react-query";
import { updateProfile } from "@/shared/api/tauriProfiles";
import { profileQueryKey } from "@/features/profile/hooks";
import { rewriteRelayUrl } from "@/shared/lib/mediaUrl";
import { useCommunities } from "@/features/communities/useCommunities";
import * as React from "react";
import "@google/model-viewer";
import { useUpdateProfileMutation } from "@/features/profile/hooks";
import { uploadMediaBytes } from "@/shared/api/tauri";
import type { Profile } from "@/shared/api/types";
import { Button } from "@/shared/ui/button";
import { Dialog, DialogContent, DialogTitle } from "@/shared/ui/dialog";
import { validateProfileModel } from "@/features/profile/lib/profileMedia";

export function ProfileMedia({
  profile,
  showBanner = true,
}: {
  profile: Profile | null | undefined;
  showBanner?: boolean;
}) {
  const [open, setOpen] = React.useState(false);
  return (
    <>
      {showBanner ? <ProfileBanner url={profile?.bannerUrl} /> : null}
      {profile?.modelUrl ? (
        <>
          <Button variant="outline" onClick={() => setOpen(true)}>
            View 3D model
          </Button>
          <Dialog open={open} onOpenChange={setOpen}>
            <DialogContent>
              <DialogTitle>Profile 3D model</DialogTitle>
              {open ? <ProfileModel url={profile.modelUrl} /> : null}
            </DialogContent>
          </Dialog>
        </>
      ) : null}
    </>
  );
}

export function ProfileBanner({ url }: { url?: string | null }) {
  return url ? (
    <img
      alt="Profile banner"
      className="h-32 w-full rounded-t-xl object-cover"
      src={rewriteRelayUrl(url)}
    />
  ) : null;
}

function ProfileModel({ url }: { url: string }) {
  const [attempt, setAttempt] = React.useState(0);
  const [failed, setFailed] = React.useState(false);
  const element = React.useRef<HTMLElement | null>(null);
  React.useEffect(() => {
    setFailed(false);
    const viewer = element.current;
    const fail = () => setFailed(true);
    viewer?.addEventListener("error", fail);
    return () => viewer?.removeEventListener("error", fail);
  }, [url, attempt]);
  return (
    <>
      {React.createElement("model-viewer", {
        key: `${url}:${attempt}`,
        ref: element,
        src: rewriteRelayUrl(url),
        alt: "Profile 3D model",
        "camera-controls": true,
        "touch-action": "pan-y",
        style: { width: "100%", height: "360px" },
      })}
      {failed ? (
        <div role="alert">
          <p>Model could not load.</p>
          <Button onClick={() => setAttempt((value) => value + 1)}>
            Retry
          </Button>
        </div>
      ) : null}
    </>
  );
}

export function ProfileMediaEditor({
  profile,
  agentPubkey,
  onSaved,
}: {
  profile: Profile | null | undefined;
  agentPubkey?: string;
  onSaved?: () => void;
}) {
  const selfMutation = useUpdateProfileMutation();
  const queryClient = useQueryClient();
  const agentMutation = useMutation({
    mutationFn: (input: Parameters<typeof updateProfile>[0]) =>
      updateProfile(input),
    onSuccess: async (saved) => {
      await queryClient.cancelQueries({
        queryKey: ["user-profile", saved.pubkey.toLowerCase()],
      });
      queryClient.setQueryData(
        ["user-profile", saved.pubkey.toLowerCase()],
        saved,
      );
      void queryClient.invalidateQueries({ queryKey: profileQueryKey });
    },
  });
  const mutation = agentPubkey ? agentMutation : selfMutation;
  const { activeCommunity } = useCommunities();
  const relayUrl = activeCommunity?.relayUrl;
  const [banner, setBanner] = React.useState(profile?.bannerUrl ?? "");
  const [model, setModel] = React.useState(profile?.modelUrl ?? "");
  const [busy, setBusy] = React.useState(false);
  const [error, setError] = React.useState("");
  const bannerInput = React.useRef<HTMLInputElement>(null);
  const modelInput = React.useRef<HTMLInputElement>(null);
  const generation = React.useRef(0);
  React.useEffect(() => {
    generation.current += 1;
    setError(profile?.pubkey && relayUrl ? "" : "Profile is not available.");
    setBanner(profile?.bannerUrl ?? "");
    setModel(profile?.modelUrl ?? "");
    setBusy(false);
    return () => {
      generation.current += 1;
    };
  }, [profile?.pubkey, profile?.bannerUrl, profile?.modelUrl, relayUrl]);

  async function upload(file: File | undefined, isModel: boolean) {
    if (!file) return;
    const current = ++generation.current;
    setBusy(true);
    setError("");
    try {
      if (file.size > (isModel ? 20 : 10) * 1024 * 1024)
        throw new Error(
          isModel ? "Model limit is 20 MB." : "Banner limit is 10 MB.",
        );
      const bytes = new Uint8Array(await file.arrayBuffer());
      if (isModel) validateProfileModel(bytes);
      const result = await uploadMediaBytes([...bytes]);
      if (!isModel && !result.type.startsWith("image/"))
        throw new Error("Choose an image for the banner.");
      if (current !== generation.current) return;
      if (isModel) setModel(result.url);
      else setBanner(result.url);
    } catch (cause) {
      if (current === generation.current)
        setError(
          cause instanceof Error ? cause.message : "Upload failed. Try again.",
        );
    } finally {
      if (current === generation.current) setBusy(false);
    }
  }

  const disabled = busy || mutation.isPending || !profile;
  const changed =
    banner !== (profile?.bannerUrl ?? "") ||
    model !== (profile?.modelUrl ?? "");
  return (
    <section
      aria-label="Profile banner and 3D model"
      className="flex flex-col gap-3 rounded-lg border p-4"
    >
      <h3 className="font-medium">Banner and 3D model</h3>
      <p className="text-sm text-muted-foreground">
        Upload a banner image (10 MB) or a self-contained GLB model (20 MB).
      </p>
      <ProfileMedia
        profile={
          profile
            ? {
                ...profile,
                bannerUrl: banner,
                modelUrl: model,
              }
            : null
        }
      />
      <input
        ref={bannerInput}
        type="file"
        accept="image/png,image/jpeg,image/webp"
        className="hidden"
        onChange={(event) => {
          void upload(event.target.files?.[0], false);
          event.target.value = "";
        }}
      />
      <input
        ref={modelInput}
        type="file"
        accept=".glb,model/gltf-binary"
        className="hidden"
        onChange={(event) => {
          void upload(event.target.files?.[0], true);
          event.target.value = "";
        }}
      />
      <div className="flex flex-wrap gap-2">
        <Button
          disabled={disabled}
          variant="outline"
          onClick={() => bannerInput.current?.click()}
        >
          Upload banner
        </Button>
        {banner ? (
          <Button
            disabled={disabled}
            variant="ghost"
            onClick={() => setBanner("")}
          >
            Remove banner
          </Button>
        ) : null}
        <Button
          disabled={disabled}
          variant="outline"
          onClick={() => modelInput.current?.click()}
        >
          Upload 3D model
        </Button>
        {model ? (
          <Button
            disabled={disabled}
            variant="ghost"
            onClick={() => setModel("")}
          >
            Remove model
          </Button>
        ) : null}
        <Button
          disabled={disabled || !changed}
          onClick={() => {
            void mutation
              .mutateAsync({
                bannerUrl:
                  banner !== (profile?.bannerUrl ?? "") ? banner : undefined,
                modelUrl:
                  model !== (profile?.modelUrl ?? "") ? model : undefined,
                expectedPubkey: agentPubkey ? undefined : profile?.pubkey,
                relayUrl,
                agentPubkey,
              })
              .then(() => onSaved?.())
              .catch(() => {});
          }}
        >
          Save profile media
        </Button>
      </div>
      {busy ? <p role="status">Uploading…</p> : null}
      {error || mutation.error ? (
        <p role="alert">{error || mutation.error?.message}</p>
      ) : null}
    </section>
  );
}
