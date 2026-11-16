document.addEventListener("DOMContentLoaded", () => {
  const repoUrl = window.location.origin + "/";
  document.querySelectorAll("#sileoBtn, #sileoFooter").forEach(el => { el.href = "sileo://source/" + repoUrl; });
  document.querySelectorAll("#zebraBtn, #zebraFooter").forEach(el => { el.href = "zbra://sources/add/" + repoUrl; });

  const root = document.documentElement;
  const themeSlider = document.getElementById("themeSlider");
  const shotImages = document.querySelectorAll(".shot-img");

  themeSlider.addEventListener("click", () => {
    const nextTheme = root.getAttribute("data-theme") === "dark" ? "light" : "dark";
    root.setAttribute("data-theme", nextTheme);
    shotImages.forEach(img => { img.src = "shots/" + img.getAttribute("data-shot") + "-" + nextTheme + ".jpg"; });
  });

  let currentLang = navigator.language.startsWith("vi") ? "vi" : "en";
  const applyLang = (lang) => {
    document.querySelectorAll("[data-vi][data-en]").forEach(el => { el.textContent = el.getAttribute("data-" + lang); });
  };
  applyLang(currentLang);

  document.getElementById("langToggle").addEventListener("click", () => {
    currentLang = currentLang === "vi" ? "en" : "vi";
    applyLang(currentLang);
  });

  const workspace = document.getElementById("cpWorkspace");
  const separator = document.getElementById("splitSeparator");
  const leftPane = document.getElementById("leftPane");
  const rightPane = document.getElementById("rightPane");
  let isDragging = false;

  separator.addEventListener("pointerdown", (e) => { isDragging = true; separator.setPointerCapture(e.pointerId); });
  separator.addEventListener("pointermove", (e) => {
    if (!isDragging) return;
    const rect = workspace.getBoundingClientRect();
    let percentage = Math.max(25, Math.min(75, ((e.clientX - rect.left) / rect.width) * 100));
    leftPane.style.width = percentage + "%";
    rightPane.style.width = (100 - percentage) + "%";
  });
  separator.addEventListener("pointerup", (e) => { isDragging = false; separator.releasePointerCapture(e.pointerId); });

  const trialForm = document.getElementById("trialForm");
  const trialMessage = document.getElementById("trialMessage");

  trialForm.addEventListener("submit", async (e) => {
    e.preventDefault();
    const code = document.getElementById("trialCode").value.trim().toUpperCase();
    trialMessage.textContent = currentLang === "vi" ? "Đang kiểm tra..." : "Verifying...";
    try {
      const res = await fetch("/api/sp2/trial", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ code }) });
      const data = await res.json();
      trialMessage.style.color = data.success ? "#30d158" : "#ff453a";
      trialMessage.textContent = data.message;
    } catch (err) {
      trialMessage.style.color = "#ff453a";
      trialMessage.textContent = currentLang === "vi" ? "Lỗi kết nối máy chủ!" : "Server error!";
    }
  });
});
