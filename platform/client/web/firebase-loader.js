/* Lazy external bootstrap: FlutterFire's inline module injection is forbidden
 * by our CSP. Load its public modules here without enabling unsafe-inline. */
(() => {
  let pending;
  window.qmLoadFirebase = () => {
    if (!pending) {
      pending = Promise.all([
        import('https://www.gstatic.com/firebasejs/12.12.0/firebase-app.js'),
        import('https://www.gstatic.com/firebasejs/12.12.0/firebase-messaging.js'),
      ]).then(([core, messaging]) => {
        window.firebase_core = core;
        window.firebase_messaging = messaging;
      }).catch(error => { pending = null; throw error; });
    }
    return pending;
  };
})();
