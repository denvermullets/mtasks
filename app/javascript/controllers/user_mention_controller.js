import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["textarea", "dropdown"];
  static values = { searchUrl: String };

  connect() {
    this.currentIndex = -1;
    this.isOpen = false;
    this.debounceTimer = null;
    this.mentionStart = null;

    this.boundClickOutside = this.clickOutside.bind(this);
    document.addEventListener("click", this.boundClickOutside);
  }

  disconnect() {
    clearTimeout(this.debounceTimer);
    document.removeEventListener("click", this.boundClickOutside);
  }

  onInput() {
    const { query, startPos } = this.extractMentionQuery();
    if (query !== null) {
      this.mentionStart = startPos;
      this.searchMembers(query);
    } else {
      this.close();
    }
  }

  onKeydown(event) {
    if (!this.isOpen) return;

    const items = this.dropdownTarget.querySelectorAll("[data-user-id]");

    switch (event.key) {
      case "ArrowDown":
        event.preventDefault();
        this.currentIndex = Math.min(this.currentIndex + 1, items.length - 1);
        this.highlightItem(items);
        break;
      case "ArrowUp":
        event.preventDefault();
        this.currentIndex = Math.max(this.currentIndex - 1, 0);
        this.highlightItem(items);
        break;
      case "Enter":
      case "Tab":
        if (this.currentIndex >= 0 && items[this.currentIndex]) {
          event.preventDefault();
          this.insertMention(items[this.currentIndex].dataset.userName);
        }
        break;
      case "Escape":
        event.preventDefault();
        this.close();
        break;
    }
  }

  selectUser(event) {
    const name = event.currentTarget.dataset.userName;
    this.insertMention(name);
  }

  // Private

  extractMentionQuery() {
    const textarea = this.textareaTarget;
    const cursorPos = textarea.selectionStart;
    const textBeforeCursor = textarea.value.substring(0, cursorPos);

    const atIndex = textBeforeCursor.lastIndexOf("@");
    if (atIndex === -1) return { query: null };

    // @ must be at start or preceded by whitespace (not a word char).
    if (atIndex > 0 && /\w/.test(textBeforeCursor[atIndex - 1])) {
      return { query: null };
    }

    const queryText = textBeforeCursor.substring(atIndex + 1);
    // Close on space/newline/second-@. Names with spaces are still reachable:
    // typing a partial first name (e.g. "Ja") surfaces "Jane Doe" in the
    // dropdown, and selecting it inserts the full name in one shot.
    if (
      queryText.includes(" ") ||
      queryText.includes("\n") ||
      queryText.includes("@")
    ) {
      return { query: null };
    }

    return { query: queryText, startPos: atIndex };
  }

  searchMembers(query) {
    clearTimeout(this.debounceTimer);
    this.debounceTimer = setTimeout(async () => {
      try {
        const response = await fetch(
          `${this.searchUrlValue}?q=${encodeURIComponent(query)}`,
          { headers: { Accept: "application/json" } }
        );
        const users = await response.json();
        this.renderResults(users);
      } catch {
        this.close();
      }
    }, 200);
  }

  renderResults(users) {
    if (users.length === 0) {
      this.close();
      return;
    }

    this.dropdownTarget.innerHTML = users
      .slice(0, 10)
      .map(
        (user, i) => `
      <button type="button"
              class="w-full text-left px-3 py-2 text-sm text-gray-300 hover:bg-hover-highlight flex items-center gap-2 cursor-pointer"
              data-action="click->user-mention#selectUser"
              data-user-id="${user.id}"
              data-user-name="${this.escapeAttr(user.name)}"
              data-index="${i}">
        <span class="w-5 h-5 rounded-full bg-accent text-background text-xs font-medium flex items-center justify-center shrink-0">${this.escapeHtml(user.name[0] || "?").toUpperCase()}</span>
        <span class="truncate">${this.escapeHtml(user.name)}</span>
      </button>
    `
      )
      .join("");

    this.dropdownTarget.classList.remove("hidden");
    this.isOpen = true;
    this.currentIndex = -1;
  }

  highlightItem(items) {
    items.forEach((item, i) => {
      if (i === this.currentIndex) {
        item.classList.add("bg-hover-highlight");
      } else {
        item.classList.remove("bg-hover-highlight");
      }
    });
  }

  insertMention(name) {
    const textarea = this.textareaTarget;
    const before = textarea.value.substring(0, this.mentionStart);
    const after = textarea.value.substring(textarea.selectionStart);
    const inserted = `@${name} `;
    textarea.value = `${before}${inserted}${after}`;

    const newCursorPos = this.mentionStart + inserted.length;
    textarea.setSelectionRange(newCursorPos, newCursorPos);
    textarea.focus();

    textarea.dispatchEvent(new Event("input", { bubbles: true }));
    this.close();
  }

  close() {
    this.dropdownTarget.classList.add("hidden");
    this.isOpen = false;
    this.currentIndex = -1;
  }

  clickOutside(event) {
    if (this.isOpen && !this.element.contains(event.target)) {
      this.close();
    }
  }

  escapeHtml(text) {
    const div = document.createElement("div");
    div.textContent = text;
    return div.innerHTML;
  }

  escapeAttr(text) {
    return String(text).replace(/"/g, "&quot;");
  }
}
