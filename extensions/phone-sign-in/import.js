// No content scripts and no cookie values returned in acknowledgments or logs.
// `reason` names the first failure (cookie name + domain, never the value) so a
// "0 of N installed" result can be diagnosed from the phone or the agent's CLI.
export async function installCookies(api, job) {
  let installed = 0;
  if (
    !job ||
    job.type !== "import" ||
    !Number.isFinite(job.deadline) ||
    Date.now() >= job.deadline ||
    !Array.isArray(job.cookies) ||
    !job.cookies.length ||
    job.cookies.length > 128 ||
    !Array.isArray(job.domains)
  )
    return { installed, uncertain: false, reason: "invalid-job" };
  const entries = job.cookies.map((c) => {
    const domain = c.domain.replace(/^\./, "");
    if (
      !job.domains.includes(domain) ||
      !/^[a-z0-9.-]+$/.test(domain) ||
      !c.path.startsWith("/")
    )
      throw Error("Invalid cookie");
    const url = `${c.secure ? "https" : "http"}://${domain}${c.path}`;
    const details = {
      url,
      name: c.name,
      value: c.value,
      path: c.path,
      secure: c.secure,
      httpOnly: c.httpOnly,
    };
    if (!c.hostOnly) details.domain = "." + domain;
    if (c.expires !== undefined) details.expirationDate = c.expires;
    if (c.sameSite)
      details.sameSite = {
        Strict: "strict",
        Lax: "lax",
        None: "no_restriction",
      }[c.sameSite];
    // Chrome rejects SameSite=None without Secure ("SameSite=None requires
    // Secure."), and some sites (Apple ID) export such cookies; the browser
    // would only ever send them over HTTPS anyway.
    if (details.sameSite === "no_restriction") details.secure = true;
    // HTTPS permission permits setting a non-Secure cookie via an HTTPS URL too.
    details.url = `https://${domain}${c.path}`;
    return { details, origin: `https://${domain}/*` };
  });
  // Preflight every permission before changing any cookie. Grant from Options.
  for (const entry of entries)
    if (!(await api.permissions.contains({ origins: [entry.origin] })))
      return {
        installed,
        uncertain: false,
        reason: `permission-missing:${entry.origin}`,
      };
  for (const { details } of entries) {
    const where = `${details.name}@${details.domain || new URL(details.url).host}`;
    if (Date.now() >= job.deadline)
      return { installed, uncertain: true, reason: "deadline" };
    try {
      const result = await api.cookies.set(details);
      if (
        !result ||
        result.value !== details.value ||
        result.name !== details.name
      )
        return { installed, uncertain: true, reason: `set-mismatch:${where}` };
      installed++;
    } catch (error) {
      return {
        installed,
        uncertain: false,
        reason: `set-rejected:${where}:${(error && error.message) || "unknown"}`,
      };
    }
  }
  return { installed, uncertain: false };
}
