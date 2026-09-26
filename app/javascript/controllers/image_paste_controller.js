import { Controller } from "@hotwired/stimulus";
import { DirectUpload } from "@rails/activestorage";

// Attach to a markdown textarea: pasted images upload straight to storage and land as ![alt](url)
export default class extends Controller {
  static values = { url: String };

  connect() {
    this.pending = 0;
    this.counter = 0;
    this.form = this.element.form;
    this.blockSubmit = this.blockSubmit.bind(this);
    this.form?.addEventListener("submit", this.blockSubmit);
  }

  disconnect() {
    this.form?.removeEventListener("submit", this.blockSubmit);
  }

  paste(event) {
    const data = event.clipboardData;
    // Apps like Excel put a picture of copied text on the clipboard; the text is what's wanted there
    if (!data || data.getData("text/plain")) return;

    const images = Array.from(data.files).filter((file) => file.type.startsWith("image/"));
    if (images.length === 0) return;

    event.preventDefault();
    images.forEach((file) => this.upload(file));
  }

  upload(file) {
    const name = file.name || "image.png";
    const placeholder = `![Uploading ${name} (${++this.counter})…]()`;
    this.insert(placeholder);
    this.pending++;

    new DirectUpload(file, this.urlValue).create((error, blob) => {
      this.pending--;
      const markdown = error
        ? `![Upload failed: ${this.altText(name)}]()`
        : `![${this.altText(blob.filename)}](${this.blobPath(blob)})`;
      this.swap(placeholder, markdown);
    });
  }

  insert(text) {
    const textarea = this.element;
    textarea.setRangeText(text, textarea.selectionStart, textarea.selectionEnd, "end");
    textarea.dispatchEvent(new Event("input", { bubbles: true }));
  }

  // Replace the placeholder wherever it ended up, keeping the caret where the user left it
  swap(placeholder, markdown) {
    const textarea = this.element;
    const index = textarea.value.indexOf(placeholder);
    if (index === -1) return;

    const caret = textarea.selectionStart;
    textarea.setRangeText(markdown, index, index + placeholder.length, "preserve");
    if (caret > index) {
      const shifted = Math.max(index, caret + markdown.length - placeholder.length);
      textarea.setSelectionRange(shifted, shifted);
    }
    textarea.dispatchEvent(new Event("input", { bubbles: true }));
  }

  blockSubmit(event) {
    if (this.pending === 0) return;

    event.preventDefault();
    event.stopImmediatePropagation();
    alert("Hang on, an image is still uploading.");
  }

  blobPath(blob) {
    return `/rails/active_storage/blobs/redirect/${blob.signed_id}/${encodeURIComponent(blob.filename)}`;
  }

  altText(filename) {
    return filename.replace(/\.[^.]+$/, "").replace(/[[\]]/g, "");
  }
}
