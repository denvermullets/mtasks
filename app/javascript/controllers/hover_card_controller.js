import { Controller } from "@hotwired/stimulus";

// Shows a floating info card when hovering a reference to an issue or project.
// Usage: data-controller="hover-card" data-hover-card-url-value="/teams/1/issues/2/card"
// The card fragment is fetched lazily on first hover and cached for the element's lifetime.
export default class extends Controller {
  static values = {
    url: String,
    delay: { type: Number, default: 300 },
  };

  connect() {
    this.onEnter = this.scheduleShow.bind(this);
    this.onLeave = this.scheduleHide.bind(this);
    this.onClick = this.hideNow.bind(this);
    this.element.addEventListener("mouseenter", this.onEnter);
    this.element.addEventListener("mouseleave", this.onLeave);
    this.element.addEventListener("click", this.onClick);
  }

  disconnect() {
    this.element.removeEventListener("mouseenter", this.onEnter);
    this.element.removeEventListener("mouseleave", this.onLeave);
    this.element.removeEventListener("click", this.onClick);
    this.clearTimers();
    this.destroy();
  }

  hideNow() {
    this.clearTimers();
    this.hide();
  }

  scheduleShow() {
    this.clearTimers();
    this.showTimer = setTimeout(() => this.render(), this.delayValue);
  }

  scheduleHide() {
    this.clearTimers();
    this.hideTimer = setTimeout(() => this.hide(), 150);
  }

  async render() {
    if (!this.card) this.build();

    if (!this.loaded) {
      try {
        const response = await fetch(this.urlValue, {
          headers: { Accept: "text/html" },
        });
        if (!response.ok) return this.destroy();
        this.card.innerHTML = await response.text();
        this.loaded = true;
      } catch {
        return this.destroy();
      }
    }

    this.position();
    this.card.classList.remove("hidden");
  }

  build() {
    this.card = document.createElement("div");
    this.card.className = "hidden";
    this.card.style.position = "fixed";
    this.card.style.zIndex = "60";
    this.card.addEventListener("mouseenter", () => this.clearTimers());
    this.card.addEventListener("mouseleave", () => this.scheduleHide());
    document.body.appendChild(this.card);
  }

  position() {
    const anchor = this.element.getBoundingClientRect();
    const card = this.card;

    // Measure while hidden but rendered.
    card.style.visibility = "hidden";
    card.classList.remove("hidden");
    const width = card.offsetWidth;
    const height = card.offsetHeight;
    card.classList.add("hidden");
    card.style.visibility = "";

    const margin = 8;
    let top = anchor.bottom + margin;
    if (top + height > window.innerHeight - margin) {
      top = anchor.top - height - margin;
    }
    top = Math.max(margin, top);

    let left = anchor.left;
    if (left + width > window.innerWidth - margin) {
      left = window.innerWidth - width - margin;
    }
    left = Math.max(margin, left);

    card.style.top = `${top}px`;
    card.style.left = `${left}px`;
  }

  hide() {
    if (this.card) this.card.classList.add("hidden");
  }

  clearTimers() {
    clearTimeout(this.showTimer);
    clearTimeout(this.hideTimer);
  }

  destroy() {
    if (this.card) {
      this.card.remove();
      this.card = null;
      this.loaded = false;
    }
  }
}
