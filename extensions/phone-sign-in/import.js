// No content scripts and no cookie values returned in acknowledgments or logs.
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
    return { installed, uncertain: false };
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
    // HTTPS permission permits setting a non-Secure cookie via an HTTPS URL too.
    details.url = `https://${domain}${c.path}`;
    return { details, origin: `https://${domain}/*` };
  });
  // Preflight every permission before changing any cookie. Grant from Options.
  for (const entry of entries)
    if (!(await api.permissions.contains({ origins: [entry.origin] })))
      return { installed, uncertain: false };
  for (const { details } of entries) {
    if (Date.now() >= job.deadline) return { installed, uncertain: true };
    try {
      const result = await api.cookies.set(details);
      if (
        !result ||
        result.value !== details.value ||
        result.name !== details.name
      )
        return { installed, uncertain: true };
      installed++;
    } catch {
      return { installed, uncertain: false };
    }
  }
  return { installed, uncertain: false };
}
