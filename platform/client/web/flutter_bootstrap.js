{{flutter_js}}
{{flutter_build_config}}
(async () => {
  // Version the executable, not just the HTML, so ordinary reloads receive fixes.
  const abort = new AbortController();
  const timer = setTimeout(() => abort.abort(), 2000);
  try {
    const response = await fetch(new URL('version.json', document.baseURI), {cache: 'no-store', signal: abort.signal});
    if (response.ok) {
      const version = await response.json();
      const key = encodeURIComponent(`${version.version}-${version.build_number}`);
      for (const build of _flutter.buildConfig.builds) {
        if (build.mainJsPath) build.mainJsPath += `?v=${key}`;
      }
    }
  } catch (_) {
    // A failed version lookup must not prevent the normal loader from starting.
  } finally {
    clearTimeout(timer);
  }
  _flutter.loader.load({config: {canvasKitBaseUrl: new URL('canvaskit/', document.baseURI).href}});
})();
