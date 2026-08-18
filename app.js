/**
 * Lawin Canvas — AR runtime
 * Video plane automatically follows the actual MP4 aspect ratio.
 */
const LOST_GRACE_MS = 6000;
const PAINTINGS = [{ id: "LC002", targetIndex: 0, videoElId: "video-LC002", planeId: "videoPlane" }];

document.addEventListener("DOMContentLoaded", () => {
  enableDebugConsoleIfRequested();
  const welcomeScreen = document.querySelector("#welcome-screen");
  const startBtn = document.querySelector("#start-btn");
  const sceneEl = document.querySelector("#ar-scene");
  const scanMessage = document.querySelector("#scan-message");
  if (!welcomeScreen || !startBtn || !sceneEl) return;

  const setScanVisible = (visible) => {
    if (scanMessage) scanMessage.classList.toggle("is-visible", visible);
  };

  const prepareVideos = () => {
    PAINTINGS.forEach((painting) => {
      const video = document.querySelector(`#${painting.videoElId}`);
      if (!video) return;
      try { video.load(); } catch (err) { console.warn("[LawinCanvas] Video load warning:", err); }
      setupVideoAspectRatio(video, painting.planeId);
    });
  };

  const revealAR = () => {
    startBtn.disabled = true;
    welcomeScreen.style.display = "none";
    setScanVisible(true);
    const eagleSound = new Audio("assets/audio/eagle-sound.mp3");
    eagleSound.preload = "auto";
    eagleSound.play().catch((err) => console.warn("[LawinCanvas] Eagle sound playback failed:", err));
    prepareVideos();
  };

  startBtn.addEventListener("click", revealAR);
  sceneEl.addEventListener("arReady", () => {
    console.log("[LawinCanvas] AR ready.");
    prepareVideos();
  });
  sceneEl.addEventListener("arError", (event) => {
    console.error("[LawinCanvas] MindAR error:", event);
    welcomeScreen.style.display = "flex";
    setScanVisible(false);
    startBtn.disabled = false;
    startBtn.textContent = "TRY AGAIN";
  });
  PAINTINGS.forEach((painting) => setupPaintingTracking(painting, setScanVisible));
});

function setupVideoAspectRatio(videoEl, planeId) {
  const plane = document.querySelector(`#${planeId}`);
  if (!plane || !videoEl) return;

  const applyRatio = () => {
    const width = videoEl.videoWidth;
    const height = videoEl.videoHeight;
    if (!width || !height) return;
    const ratio = width / height;
    plane.setAttribute("width", 1);
    plane.setAttribute("height", 1 / ratio);
    console.log(`[LawinCanvas] ${videoEl.id}: ${width}x${height}; plane=1x${(1 / ratio).toFixed(4)}`);
  };

  if (videoEl.readyState >= 1) applyRatio();
  videoEl.addEventListener("loadedmetadata", applyRatio);
}

function setupPaintingTracking(painting, setScanVisible) {
  const targetEl = document.querySelector(`#target-${painting.targetIndex}`);
  const videoEl = document.querySelector(`#${painting.videoElId}`);
  if (!targetEl || !videoEl) return;
  let lostGraceTimer = null;

  targetEl.addEventListener("targetFound", () => {
    setScanVisible(false);
    if (lostGraceTimer) {
      clearTimeout(lostGraceTimer);
      lostGraceTimer = null;
      return;
    }
    videoEl.currentTime = 0;
    videoEl.play().catch((err) => console.error(`[LawinCanvas] ${painting.id} video play failed:`, err));
  });

  targetEl.addEventListener("targetLost", () => {
    setScanVisible(true);
    if (lostGraceTimer) clearTimeout(lostGraceTimer);
    lostGraceTimer = setTimeout(() => {
      lostGraceTimer = null;
      videoEl.pause();
    }, LOST_GRACE_MS);
  });
}

function enableDebugConsoleIfRequested() {
  const params = new URLSearchParams(window.location.search);
  if (params.get("debug") !== "1") return;
  const script = document.createElement("script");
  script.src = "https://cdn.jsdelivr.net/npm/eruda";
  script.onload = () => { if (window.eruda) window.eruda.init(); };
  document.body.appendChild(script);
}
