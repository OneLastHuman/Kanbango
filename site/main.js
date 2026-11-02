(() => {
  const cards = Array.from(document.querySelectorAll(".card[data-session]"));
  const termLines = document.getElementById("term-lines");
  const termBranch = document.querySelector(".term-branch");
  const termState = document.querySelector(".term-state");
  const termTime = document.querySelector(".term-time");
  const live = document.getElementById("term-live");
  if (!cards.length || !termLines || !termBranch || !termState || !termTime) return;
  const zh = document.documentElement.lang.toLowerCase().startsWith("zh");


  const authMarkup = termLines.innerHTML;
  const labels = {
    running: zh ? "运行中" : "running",
    idle: zh ? "空闲" : "idle",
    waiting: zh ? "等待输入" : "needs input",
  };
  const sessions = {
    auth: { status: "running", seconds: 134 },
    docs: { status: "idle", time: zh ? "41分钟" : "41m" },
    callbacks: { status: "waiting", time: zh ? "3小时" : "3h" },
  };
  const stateClass = { running: "is-running", idle: "is-idle", waiting: "is-waiting" };
  const dotClass = { running: "dot dot-run", idle: "dot dot-idle", waiting: "dot dot-wait" };
  let active = "auth";
  let booted = false;

  const format = (seconds) => {
    const h = Math.floor(seconds / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    const s = seconds % 60;
    if (zh) {
      if (h > 0) return `${h}小时${String(m).padStart(2, "0")}分`;
      return `${m}分${String(s).padStart(2, "0")}秒`;
    }
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
    termState.innerHTML = `<span class="${dotClass[session.status]}"></span>${labels[session.status]}`;

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
    live.textContent = zh
      ? `正在显示「${card.dataset.title}」的会话，${labels[session.status]}。`
      : `Showing ${card.dataset.title}, ${labels[session.status]}.`;
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
    const copyLabel = zh ? "复制" : "Copy";
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
      const copiedLabel = zh ? "已复制" : "Copied";
      const failedLabel = zh ? "请选择并复制" : "Select and copy";
      const okMessage = zh
        ? "构建命令已复制到剪贴板。"
        : "Build commands copied to the clipboard.";
      const failMessage = zh
        ? "复制失败，请手动选择命令复制。"
        : "Copy failed. Select the commands and copy them manually.";
      copyButton.textContent = copied ? copiedLabel : failedLabel;
      if (copyLive) {
        copyLive.textContent = copied ? okMessage : failMessage;
      }
      window.setTimeout(() => {
        copyButton.textContent = copyLabel;
      }, 1800);
    });
  }

  renderTime();
})();
