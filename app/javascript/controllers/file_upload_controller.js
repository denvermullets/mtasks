import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["dropzone", "input", "fileList"];

  openFilePicker() {
    this.inputTarget.click();
  }

  handleFiles() {
    this.renderFileList();
  }

  dragOver(event) {
    event.preventDefault();
  }

  dragEnter(event) {
    event.preventDefault();
    this.element.classList.add("border-accent");
    this.element.classList.remove("border-stroke");
  }

  dragLeave(event) {
    event.preventDefault();
    if (!this.element.contains(event.relatedTarget)) {
      this.element.classList.remove("border-accent");
      this.element.classList.add("border-stroke");
    }
  }

  drop(event) {
    event.preventDefault();
    this.element.classList.remove("border-accent");
    this.element.classList.add("border-stroke");

    const droppedFiles = event.dataTransfer.files;
    if (droppedFiles.length === 0) return;

    // Merge with existing files
    const dt = new DataTransfer();
    const existing = this.inputTarget.files;
    for (let i = 0; i < existing.length; i++) {
      dt.items.add(existing[i]);
    }
    for (let i = 0; i < droppedFiles.length; i++) {
      dt.items.add(droppedFiles[i]);
    }
    this.inputTarget.files = dt.files;
    this.renderFileList();
  }

  removeFile(event) {
    const index = parseInt(event.currentTarget.dataset.index);
    const dt = new DataTransfer();
    const files = this.inputTarget.files;

    for (let i = 0; i < files.length; i++) {
      if (i !== index) {
        dt.items.add(files[i]);
      }
    }
    this.inputTarget.files = dt.files;
    this.renderFileList();
  }

  renderFileList() {
    const files = this.inputTarget.files;
    this.fileListTarget.innerHTML = "";

    for (let i = 0; i < files.length; i++) {
      const file = files[i];
      const size = this.formatFileSize(file.size);
      const icon = this.fileIcon(file.type);

      const el = document.createElement("div");
      el.className =
        "flex items-center justify-between px-3 py-2 bg-foreground border border-stroke rounded-md text-sm";
      el.innerHTML = `
        <div class="flex items-center gap-2 text-gray-300 min-w-0">
          <span class="text-gray-500 shrink-0">${icon}</span>
          <span class="truncate">${this.escapeHtml(file.name)}</span>
          <span class="text-gray-500 shrink-0">${size}</span>
        </div>
        <button type="button" data-action="click->file-upload#removeFile" data-index="${i}"
                class="text-gray-500 hover:text-red-400 transition-colors shrink-0 ml-2">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
          </svg>
        </button>
      `;
      this.fileListTarget.appendChild(el);
    }
  }

  formatFileSize(bytes) {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  }

  fileIcon(mimeType) {
    if (mimeType.startsWith("image/")) return "🖼";
    if (mimeType === "application/pdf") return "📄";
    if (mimeType.includes("markdown") || mimeType === "text/markdown") return "📝";
    return "📎";
  }

  escapeHtml(str) {
    const div = document.createElement("div");
    div.textContent = str;
    return div.innerHTML;
  }
}
