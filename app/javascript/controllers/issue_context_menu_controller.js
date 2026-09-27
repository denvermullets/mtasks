import { Controller } from "@hotwired/stimulus";
import { Turbo } from "@hotwired/turbo-rails";

// Right-click menu for board cards: the S / P / L / J shortcuts, plus open and copy actions.
// One instance per page (like the shared pickers), retargeted at whichever card was clicked.
// It carries data-shared-picker so, while open, it freezes hover tracking and board-keyboard
// stands down — the menu handles its own letters, arrows, enter and escape.
export default class extends Controller {
  static targets = ["header", "item"];

  connect() {
    this.focusIndex = -1;

    this.boundHandleContextMenu = this.handleContextMenu.bind(this);
    this.boundHandleMouseDown = this.handleMouseDown.bind(this);
    this.boundHandleKeyDown = this.handleKeyDown.bind(this);
    this.boundClose = this.close.bind(this);

    document.addEventListener("contextmenu", this.boundHandleContextMenu);
  }

  disconnect() {
    this.close();
    document.removeEventListener("contextmenu", this.boundHandleContextMenu);
  }

  handleContextMenu(event) {
    if (this.element.contains(event.target)) {
      event.preventDefault();
      return;
    }

    const card = event.target.closest('[data-controller~="issue-card"]');

    // Shift+right-click keeps the browser's own menu (open in new tab, inspect, ...).
    if (!card || event.shiftKey) {
      this.close();
      return;
    }

    event.preventDefault();
    this.openForCard(card, event.clientX, event.clientY);
  }

  openForCard(card, x, y) {
    this.card = card;
    this.markHovered(card);

    const identifier = card.dataset.issueIdentifier || "";
    const title = card.dataset.issueTitle || "";
    this.headerTarget.textContent = title ? `${identifier} • ${title}` : identifier;

    // Hide picker actions this page has no picker for (projects/show has no project picker).
    this.itemTargets.forEach((item) => {
      const picker = item.dataset.picker;
      const available = !picker || document.querySelector(`[data-shared-picker="${picker}"]`);
      item.classList.toggle("hidden", !available);
    });

    this.element.classList.remove("hidden");
    this.position(x, y);
    this.setFocus(-1);

    if (!this.listening) {
      this.listening = true;
      document.addEventListener("mousedown", this.boundHandleMouseDown);
      document.addEventListener("keydown", this.boundHandleKeyDown);
      window.addEventListener("resize", this.boundClose);
      window.addEventListener("blur", this.boundClose);
      document.addEventListener("scroll", this.boundClose, true);
    }
  }

  close() {
    this.element.classList.add("hidden");

    if (this.listening) {
      this.listening = false;
      document.removeEventListener("mousedown", this.boundHandleMouseDown);
      document.removeEventListener("keydown", this.boundHandleKeyDown);
      window.removeEventListener("resize", this.boundClose);
      window.removeEventListener("blur", this.boundClose);
      document.removeEventListener("scroll", this.boundClose, true);
    }
  }

  // Same bookkeeping as issue-card#mouseEnter: the right-clicked card becomes the one
  // keyboard shortcuts and pickers target.
  markHovered(card) {
    document.querySelectorAll('[data-hovered="true"]').forEach((other) => {
      if (other !== card) delete other.dataset.hovered;
    });
    card.dataset.hovered = "true";
  }

  position(x, y) {
    const gap = 8;
    const { offsetWidth: width, offsetHeight: height } = this.element;

    const left = Math.max(gap, Math.min(x, window.innerWidth - width - gap));
    const top = Math.max(gap, Math.min(y, window.innerHeight - height - gap));

    this.element.style.left = `${left}px`;
    this.element.style.top = `${top}px`;
  }

  handleMouseDown(event) {
    if (!this.element.contains(event.target)) this.close();
  }

  handleKeyDown(event) {
    if (event.metaKey || event.ctrlKey || event.altKey) return;

    const items = this.visibleItems;

    if (event.key === "Escape") {
      event.preventDefault();
      this.close();
    } else if (event.key === "ArrowDown") {
      event.preventDefault();
      this.setFocus(Math.min(this.focusIndex + 1, items.length - 1));
    } else if (event.key === "ArrowUp") {
      event.preventDefault();
      this.setFocus(Math.max(this.focusIndex - 1, 0));
    } else if (event.key === "Enter") {
      event.preventDefault();
      if (this.focusIndex >= 0) this.run(items[this.focusIndex]);
    } else {
      const item = items.find((i) => i.dataset.shortcut === event.key.toLowerCase());
      if (item) {
        event.preventDefault();
        this.run(item);
      }
    }
  }

  get visibleItems() {
    return this.itemTargets.filter((item) => !item.classList.contains("hidden"));
  }

  setFocus(index) {
    this.focusIndex = index;
    this.visibleItems.forEach((item, i) => {
      item.classList.toggle("bg-hover-highlight", i === index);
    });
  }

  select(event) {
    this.run(event.currentTarget);
  }

  run(item) {
    const card = this.card;
    this.close();
    if (!card || !document.contains(card)) return;

    const { picker, command } = item.dataset;

    // Defer past the current click/keydown: a picker opened synchronously registers its
    // document click-outside listener mid-dispatch and would close on this very event.
    setTimeout(() => {
      if (picker) {
        this.boardKeyboard?.openPickerForCard(picker, card);
      } else if (command) {
        this[command](card);
      }
    }, 0);
  }

  get boardKeyboard() {
    const host = this.element.closest('[data-controller~="board-keyboard"]');
    return host && this.application.getControllerForElementAndIdentifier(host, "board-keyboard");
  }

  issueUrl(card) {
    return card.querySelector("a[href]")?.href;
  }

  openIssue(card) {
    const url = this.issueUrl(card);
    if (url) Turbo.visit(url);
  }

  openInNewTab(card) {
    const url = this.issueUrl(card);
    if (url) window.open(url, "_blank", "noopener");
  }

  copyLink(card) {
    const url = this.issueUrl(card);
    if (url) navigator.clipboard.writeText(url);
  }

  copyIdentifier(card) {
    const identifier = card.dataset.issueIdentifier;
    if (identifier) navigator.clipboard.writeText(identifier);
  }
}
