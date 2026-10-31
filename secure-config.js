// Public (non-secret) Supabase configuration.
// This file MUST be filled with the project's public URL and publishable key
// ONLY AFTER the secure backend and private CSV file have been configured.
// Never put a service_role key, Resend API key, database password or OTP pepper here.
window.GBD_SECURE_CONFIG = Object.freeze({
  url: "SET_SUPABASE_PROJECT_URL",
  publishableKey: "SET_SUPABASE_PUBLISHABLE_KEY",
  bucket: "gbd-private",
  objectPath: "gbd2023_low_physical_activity.csv",
});
