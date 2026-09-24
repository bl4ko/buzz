/**
 * Who may use the community restriction surfaces (ban, timeout, lift).
 *
 * Community owners and admins moderate their own community; relay staff
 * (operators and moderators on the relay roster) moderate every community on
 * their relay. The relay is the authority — this only decides which menus to
 * show, so a wrong answer yields a relay rejection, never extra power.
 */

export type RelayStaffRole = "operator" | "moderator";

export function canRestrictMembers(
  communityRole: string | undefined,
  relayStaff: RelayStaffRole | null | undefined,
): boolean {
  return (
    communityRole === "owner" || communityRole === "admin" || relayStaff != null
  );
}

/**
 * Only relay staff may restrict an owner; community admins cannot, so the
 * owner row hides its restriction actions for everyone else.
 */
export function canRestrictOwner(
  relayStaff: RelayStaffRole | null | undefined,
): boolean {
  return relayStaff != null;
}
