import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["textarea", "dropdown"];
  static values = { searchUrl: String, teamIdentifier: String };

  connect() {
    this.currentIndex = -1;
    this.isOpen = false;
    this.debounceTimer = null;
    this.mentionStart = null;
    this.urlPattern = /\/teams\/\d+\/issues\/(\d+)/;

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
      this.searchIssues(query);
    } else {
      this.close();
    }
  }

  onKeydown(event) {
    if (!this.isOpen) return;

    const items = this.dropdownTarget.querySelectorAll("[data-identifier]");

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
          this.insertMention(
            items[this.currentIndex].dataset.identifier
          );
        }
        break;
      case "Escape":
        event.preventDefault();
        this.close();
        break;
    }
  }

  onPaste(event) {
    const text = event.clipboardData?.getData("text/plain");
    if (!text) return;

    const match = text.trim().match(this.urlPattern);
    if (!match) return;

    event.preventDefault();
    const issueId = match[1];

    fetch(`${this.searchUrlValue}?q=`, {
      headers: { Accept: "application/json" },
    })
      .then((response) => response.json())
      .then((issues) => {
        const issue = issues.find((i) => i.id === parseInt(issueId));
        if (issue) {
          this.insertTextAtCursor(issue.identifier);
        } else {
          this.insertTextAtCursor(text);
        }
      })
      .catch(() => {
        this.insertTextAtCursor(text);
      });
  }

  selectIssue(event) {
    const identifier = event.currentTarget.dataset.identifier;
    this.insertMention(identifier);
  }

  // Private

  extractMentionQuery() {
    const textarea = this.textareaTarget;
    const cursorPos = textarea.selectionStart;
    const textBeforeCursor = textarea.value.substring(0, cursorPos);

    const hashIndex = textBeforeCursor.lastIndexOf("#");
    if (hashIndex === -1) return { query: null };

    // Ensure # is at start of text or preceded by whitespace
    if (hashIndex > 0 && !/\s/.test(textBeforeCursor[hashIndex - 1])) {
      return { query: null };
    }

    const queryText = textBeforeCursor.substring(hashIndex + 1);
    if (queryText.includes(" ") || queryText.includes("\n")) {
      return { query: null };
    }

    return { query: queryText, startPos: hashIndex };
  }

  searchIssues(query) {
    clearTimeout(this.debounceTimer);
    this.debounceTimer = setTimeout(async () => {
      try {
        const response = await fetch(
          `${this.searchUrlValue}?q=${encodeURIComponent(query)}`,
          { headers: { Accept: "application/json" } }
        );
        const issues = await response.json();
        this.renderResults(issues);
      } catch {
        this.close();
      }
    }, 300);
  }

  renderResults(issues) {
    if (issues.length === 0) {
      this.close();
      return;
    }

    this.dropdownTarget.innerHTML = issues
      .slice(0, 10)
      .map(
        (issue, i) => `
      <button type="button"
              class="w-full text-left px-3 py-2 text-sm text-gray-300 hover:bg-hover-highlight flex items-center gap-2 cursor-pointer"
              data-action="click->issue-mention#selectIssue"
              data-identifier="${issue.identifier}"
              data-index="${i}">
        <span class="font-mono text-gray-500 shrink-0">${issue.identifier}</span>
        <span class="truncate">${this.escapeHtml(issue.title)}</span>
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

  insertMention(identifier) {
    const textarea = this.textareaTarget;
    const before = textarea.value.substring(0, this.mentionStart);
    const after = textarea.value.substring(textarea.selectionStart);
    textarea.value = `${before}${identifier} ${after}`;

    const newCursorPos = this.mentionStart + identifier.length + 1;
    textarea.setSelectionRange(newCursorPos, newCursorPos);
    textarea.focus();

    textarea.dispatchEvent(new Event("input", { bubbles: true }));
    this.close();
  }

  insertTextAtCursor(text) {
    const textarea = this.textareaTarget;
    const start = textarea.selectionStart;
    const end = textarea.selectionEnd;
    const before = textarea.value.substring(0, start);
    const after = textarea.value.substring(end);
    textarea.value = `${before}${text} ${after}`;

    const newCursorPos = start + text.length + 1;
    textarea.setSelectionRange(newCursorPos, newCursorPos);
    textarea.focus();

    textarea.dispatchEvent(new Event("input", { bubbles: true }));
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
}
