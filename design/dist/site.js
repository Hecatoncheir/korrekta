async function refreshDownloads() {
  const links = [...document.querySelectorAll('[data-release-link]')];
  if (!links.length) return;
  try {
    const response = await fetch('https://api.github.com/repos/Hecatoncheir/korrekta/releases?per_page=20', { signal: AbortSignal.timeout(5000), credentials: 'omit' });
    if (!response.ok) return;
    const releases = await response.json();
    if (!Array.isArray(releases)) return;
    const release = releases.find(item => !item.draft && /^v\d+\.\d+\.\d+$/.test(item.tag_name) && links.every(link => item.assets?.some(asset => asset.name.endsWith(`-${link.dataset.releaseLink}`))));
    if (!release) return;
    const prefix = `https://github.com/Hecatoncheir/korrekta/releases/download/${release.tag_name}/`;
    for (const link of links) {
      const asset = release.assets.find(asset => asset.name.endsWith(`-${link.dataset.releaseLink}`));
      if (asset.browser_download_url.startsWith(prefix)) link.href = asset.browser_download_url;
    }
    document.querySelectorAll('[data-release-page]').forEach(link => link.href = `https://github.com/Hecatoncheir/korrekta/releases/tag/${release.tag_name}`);
    document.querySelectorAll('[data-release-label]').forEach(label => label.textContent = `${release.tag_name} · ${release.prerelease ? 'Предварительный выпуск' : 'Последний выпуск'}`);
  } catch {
    // При недоступном API остаются рабочие ссылки на проверенный выпуск.
  }
}
refreshDownloads();
