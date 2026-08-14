/**
 * Lawin Canvas — LC002
 *
 * Same working AR camera/MindAR pipeline as LC001.
 */

const LOST_GRACE_MS = 6000;

const PAINTINGS = [
  { id: "LC002", targetIndex: 0, videoElId: "video-LC002" },
];

document.addEventListener("DOMContentLoaded", () => {
  enableDebugConsoleIfRequested();

  const welcomeScreen = document.querySelector("#welcome-screen");
  const startBtn = document.querySelector("#start-btn");
  const sceneEl = document.querySelector("#ar-scene");
  const scanMessage = document.querySelector("#scan-message");

  if (!welcomeScreen || !startBtn || !sceneEl) {
    console.error("[LawinCanvas] Required welcome/scene elements not found.");
    return;
  }

  const setScanVisible = (visible) => {
    if (!scanMessage) return;
    scanMessage.classList.toggle("is-visible", visible);
  };

  const revealAR = () => {
    startBtn.disabled = true;
    welcomeScreen.style.display = "none";
    setScanVisible(true);

    const eagleSound = new Audio("assets/audio/eagle-sound.mp3");
    eagleSound.preload = "auto";
    eagleSound.play().catch((err) => {
      console.warn("[LawinCanvas] Eagle sound playback failed:", err);
    });

    const video = document.querySelector("#video-LC002");
    if (video) {
      try {
        video.load();
      } catch (err) {
        console.warn("[LawinCanvas] Video load warning:", err);
      }
    }
  };

  startBtn.addEventListener("click", revealAR);

  sceneEl.addEventListener("arReady", () => {
    console.log("[LawinCanvas] AR ready.");
  });

  sceneEl.addEventListener("arError", (event) => {
    console.error("[LawinCanvas] MindAR error:", event);
    welcomeScreen.style.display = "flex";
    setScanVisible(false);
    startBtn.disabled = false;
    startBtn.textContent = "TRY AGAIN";
  });

  PAINTINGS.forEach((painting) => {
    setupPaintingTracking(painting, setScanVisible);
  });
});

function setupPaintingTracking(painting, setScanVisible) {
  const targetEl = document.querySelector(`#target-${painting.targetIndex}`);
  const videoEl = document.querySelector(`#${painting.videoElId}`);

  if (!targetEl) {
    console.error(`[LawinCanvas] Target entity not found for ${painting.id}.`);
    return;
  }

  if (!videoEl) {
    console.error(`[LawinCanvas] Video element #${painting.videoElId} not found.`);
    return;
  }

  let lostGraceTimer = null;

  targetEl.addEventListener("targetFound", () => {
    console.log(`[LawinCanvas] ${painting.id} found.`);
    setScanVisible(false);

    if (lostGraceTimer) {
      clearTimeout(lostGraceTimer);
      lostGraceTimer = null;
      console.log(`[LawinCanvas] ${painting.id} returned during grace period.`);
      return;
    }

    videoEl.currentTime = 0;
    videoEl.play()
      .then(() => console.log(`[LawinCanvas] ${painting.id} video playing.`))
      .catch((err) => console.error(`[LawinCanvas] ${painting.id} video play failed:`, err));
  });

  targetEl.addEventListener("targetLost", () => {
    console.log(`[LawinCanvas] ${painting.id} lost. Starting ${LOST_GRACE_MS / 1000}s grace period.`);
    setScanVisible(true);

    if (lostGraceTimer) clearTimeout(lostGraceTimer);

    lostGraceTimer = setTimeout(() => {
      lostGraceTimer = null;
      videoEl.pause();
      console.log(`[LawinCanvas] ${painting.id} grace period elapsed. Video paused.`);
    }, LOST_GRACE_MS);
  });
}

function enableDebugConsoleIfRequested() {
  const params = new URLSearchParams(window.location.search);
  if (params.get("debug") !== "1") return;

  const script = document.createElement("script");
  script.src = "https://cdn.jsdelivr.net/npm/eruda";
  script.onload = () => {
    if (window.eruda) {
      window.eruda.init();
      console.log("[LawinCanvas] Debug console enabled.");
    }
  };
  document.body.appendChild(script);
}
