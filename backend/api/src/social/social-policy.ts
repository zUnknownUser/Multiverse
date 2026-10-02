// SQL expressions only; callers supply fixed aliases/placeholders, never user input.
export const unblocked = (viewer: string, target: string) => `NOT EXISTS (
  SELECT 1 FROM user_blocks b WHERE (b.blocker_uid=${viewer} AND b.blocked_uid=${target})
  OR (b.blocked_uid=${viewer} AND b.blocker_uid=${target}))`;
