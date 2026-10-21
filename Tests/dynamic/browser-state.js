// Read-only Playwright CLI run-code helper for the owned offline fixture.
async page => {
  const url = new URL(page.url());
  if (url.protocol !== 'file:' || !url.pathname.endsWith('/browser-fixture.html') ||
      await page.title() !== 'Dynamic browser fixture') {
    throw new Error('This helper only reads the local synthetic browser fixture.');
  }
  return page.evaluate(() => {
    const player = document.getElementById('player');
    const quality = player.getVideoPlaybackQuality?.();
    let decodedCenter = null;
    let decodedCenterError = null;
    if (!player.hidden && player.readyState >= HTMLMediaElement.HAVE_CURRENT_DATA) {
      try {
        const canvas = document.createElement('canvas');
        canvas.width = canvas.height = 1;
        const context = canvas.getContext('2d');
        context.drawImage(player, Math.floor(player.videoWidth / 2),
          Math.floor(player.videoHeight / 2), 1, 1, 0, 0, 1, 1);
        decodedCenter = Array.from(context.getImageData(0, 0, 1, 1).data);
      } catch (error) {
        decodedCenterError = error.name;
      }
    }
    const points = {bottom: [innerWidth / 2, innerHeight - 1],
      left: [1, innerHeight / 2], right: [innerWidth - 1, innerHeight / 2]};
    const edges = Object.fromEntries(Object.entries(points).map(([edge, point]) => {
      const element = document.elementFromPoint(...point);
      return [edge, {element: element?.tagName ?? null,
        cssBackground: element ? getComputedStyle(element).backgroundColor : null}];
    }));
    return {fixture: 'Dynamic browser fixture', browser: navigator.userAgent,
      guestWallClockMs: Date.now(), pagePerformanceMs: performance.now(),
      focused: document.hasFocus(), mode: document.body.className || 'scroll',
      status: document.getElementById('status').textContent, scrollY,
      viewport: {width: innerWidth, height: innerHeight, devicePixelRatio}, edges,
      video: {visible: !player.hidden, paused: player.paused, time: player.currentTime,
        duration: Number.isFinite(player.duration) ? player.duration : null,
        width: player.videoWidth, height: player.videoHeight, readyState: player.readyState,
        totalFrames: quality?.totalVideoFrames ?? null,
        droppedFrames: quality?.droppedVideoFrames ?? null,
        mediaError: player.error?.code ?? null, decodedCenter, decodedCenterError},
      limits: ['DOM/CSS and decoded-frame diagnostics only; verify the real desktop strip and taskbar separately.',
        'Page performance time is not Windows QPC. This helper establishes no latency percentile or resource budget.']};
  });
}
