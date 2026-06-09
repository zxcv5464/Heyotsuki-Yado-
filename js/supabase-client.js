(() => {
  // Replace these two placeholders with values from your Supabase project:
  // 1. Project URL, for example: https://your-project-ref.supabase.co
  // 2. Publishable key (preferred) or legacy anon key.
  // Never place an sb_secret_... or legacy service_role key in frontend code.
  const config = {
    url: "https://hcuectvlszbyrcpuaxcr.supabase.co",
    publishableKey: "sb_publishable_SI6BRbRZaR_QoX34ZKGLDw_vtwH5IHo",
  };

  const getLegacyJwtRole = (key) => {
    try {
      const payload = key.split(".")[1];
      if (!payload) return null;
      const base64 = payload.replaceAll("-", "+").replaceAll("_", "/");
      const padded = base64.padEnd(Math.ceil(base64.length / 4) * 4, "=");
      return JSON.parse(atob(padded)).role || null;
    } catch {
      return null;
    }
  };

  const isPublicBrowserKey =
    config.publishableKey.startsWith("sb_publishable_") ||
    getLegacyJwtRole(config.publishableKey) === "anon";
  const isConfigured =
    !config.url.includes("YOUR_PROJECT_REF") &&
    !config.publishableKey.includes("YOUR_SUPABASE_") &&
    isPublicBrowserKey;

  window.SUPABASE_CONFIG = {
    ...config,
    isConfigured,
  };

  window.SUPABASE_CLIENT =
    isConfigured && window.supabase?.createClient
      ? window.supabase.createClient(config.url, config.publishableKey)
      : null;
})();
