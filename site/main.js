(() => {
  const cards = Array.from(document.querySelectorAll(".card[data-session]"));
  const termLines = document.getElementById("term-lines");
  const termBranch = document.querySelector(".term-branch");
  const termState = document.querySelector(".term-state");
  const termTime = document.querySelector(".term-time");
  const live = document.getElementById("term-live");
  if (!cards.length || !termLines || !termBranch || !termState || !termTime) return;

  const authMarkup = termLines.innerHTML;
  const sessions = {
    auth: { status: "running", label: "running", seconds: 134 },
    docs: { status: "idle", label: "idle", time: "41m" },
    callbacks: { status: "waiting", label: "needs input", time: "3h" },
  };
  const stateClass = { running: "is-running", idle: "is-idle", waiting: "is-waiting" };
  const dotClass = { running: "dot dot-run", idle: "dot dot-idle", waiting: "dot dot-wait" };
  let active = "auth";
  let booted = false;

  const format = (seconds) => {
    const h = Math.floor(seconds / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    const s = seconds % 60;
    if (h > 0) return `${h}h ${String(m).padStart(2, "0")}m`;
    return `${m}m ${String(s).padStart(2, "0")}s`;
  };

  const renderTime = () => {
    const session = sessions[active];
    const text = session.seconds != null ? format(session.seconds) : session.time;
    termTime.textContent = text;
    const card = cards.find((c) => c.dataset.session === active);
    const slot = card && card.querySelector(".sess-time");
    if (slot) slot.textContent = text;
  };

  const activate = (key) => {
    const card = cards.find((c) => c.dataset.session === key);
    if (!card || key === active) return;
    active = key;
    const session = sessions[key];

    cards.forEach((c) => {
      const on = c === card;
      c.classList.toggle("is-active", on);
      c.setAttribute("aria-pressed", String(on));
    });

    termBranch.textContent = card.dataset.branch;
    termState.className = `term-state ${stateClass[session.status]}`;
    termState.innerHTML = `<span class="${dotClass[session.status]}"></span>${session.label}`;

    if (!booted) {
      termLines.classList.remove("boot");
      booted = true;
    }

    if (key === "auth") {
      termLines.innerHTML = authMarkup;
    } else {
      const template = document.getElementById(`tpl-${key}`);
      if (template) termLines.innerHTML = template.innerHTML;
    }

    renderTime();
    termLines.scrollTop = 0;
    live.textContent = `Showing ${card.dataset.title}, ${session.label}.`;
  };

  cards.forEach((card) => {
    card.addEventListener("click", () => activate(card.dataset.session));
  });

  window.setInterval(() => {
    const session = sessions[active];
    if (session.status !== "running") return;
    session.seconds += 1;
    renderTime();
  }, 1000);

  const copyButton = document.querySelector(".copy");
  const copyLive = document.getElementById("copy-live");
  if (copyButton) {
    copyButton.addEventListener("click", async () => {
      const commands = document.getElementById("build-commands");
      if (!commands) return;
      const text = commands.textContent;
      let copied = false;
      try {
        await navigator.clipboard.writeText(text);
        copied = true;
      } catch (error) {
        const field = document.createElement("textarea");
        field.value = text;
        field.setAttribute("readonly", "");
        field.style.position = "fixed";
        field.style.opacity = "0";
        document.body.appendChild(field);
        field.select();
        try {
          copied = document.execCommand("copy");
        } catch (fallbackError) {
          copied = false;
        }
        field.remove();
      }
      copyButton.textContent = copied ? "Copied" : "Select and copy";
      if (copyLive) {
        copyLive.textContent = copied
          ? "Build commands copied to the clipboard."
          : "Copy failed. Select the commands and copy them manually.";
      }
      window.setTimeout(() => {
        copyButton.textContent = "Copy";
      }, 1800);
    });
  }

  renderTime();
})();
