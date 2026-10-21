-- Bound by the migration runner after verifying the target environment.
-- No user data or credentials. A server refuses a database owned by another environment.
CREATE TABLE IF NOT EXISTS deployment_identity (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  environment text NOT NULL CHECK (environment IN ('local', 'staging', 'production')),
  firebase_project_id text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
