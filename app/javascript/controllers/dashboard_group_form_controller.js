import { Controller } from "@hotwired/stimulus";

// Lives on the dashboard show page. One modal (dashboards/_group_form_modal) serves both
// "Add group" and "Edit group"; triggers pass url/method/title/submit/name/description/color/
// teamIds/projectIds/deleteUrl as action params and open() fills the form from them.
export default class extends Controller {
  static targets = [
    "modal",
    "form",
    "method",
    "title",
    "submit",
    "name",
    "description",
    "color",
    "team",
    "project",
    "search",
    "projectRow",
    "teamHeading",
    "emptyState",
    "deleteSection",
    "deleteForm",
    "errors",
  ];

  connect() {
    this.boundHandleEscape = this.handleEscape.bind(this);
    // The server re-rendered the modal open after a 422: wire Escape + focus as if the user opened it.
    if (this.hasModalTarget && !this.modalTarget.classList.contains("hidden")) {
      this.applyProjectVisibility();
      this.show();
    }
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundHandleEscape);
  }

  open(event) {
    const {
      url,
      method = "post",
      title = "New group",
      submit = "Create",
      name = "",
      description = "",
      color = this.colorTargets[0]?.value,
      teamIds = [],
      projectIds = [],
      deleteUrl = "",
    } = event.params;

    this.formTarget.action = url;
    this.methodTarget.value = method;
    this.titleTarget.textContent = title;
    this.submitTarget.textContent = submit;
    this.nameTarget.value = name;
    this.descriptionTarget.value = description;
    this.colorTargets.forEach((radio) => {
      radio.checked = radio.value === color;
    });
    this.teamTargets.forEach((box) => {
      box.checked = teamIds.includes(Number(box.value));
    });
    this.projectTargets.forEach((box) => {
      box.checked = projectIds.includes(Number(box.value));
    });
    this.searchTarget.value = "";
    this.applyProjectVisibility();

    this.deleteSectionTarget.classList.toggle("hidden", !deleteUrl);
    if (deleteUrl) this.deleteFormTarget.action = deleteUrl;

    if (this.hasErrorsTarget) this.errorsTarget.remove();
    this.show();
  }

  show() {
    this.modalTarget.classList.remove("hidden");
    document.addEventListener("keydown", this.boundHandleEscape);
    this.nameTarget.focus();
    this.nameTarget.select();
  }

  close() {
    this.modalTarget.classList.add("hidden");
    document.removeEventListener("keydown", this.boundHandleEscape);
  }

  backdropClick(event) {
    if (event.target === event.currentTarget) this.close();
  }

  handleEscape(event) {
    if (event.key === "Escape") this.close();
  }

  filter() {
    this.applyProjectVisibility();
  }

  // A project row shows when it matches the filter text and is either still open or currently
  // checked (completed projects only stay listed so they can be unchecked). Team headings
  // follow their rows.
  applyProjectVisibility() {
    const query = this.searchTarget.value.trim().toLowerCase();
    const visibleTeams = new Set();
    let visibleCount = 0;

    this.projectRowTargets.forEach((row) => {
      const checked = row.querySelector("input[type=checkbox]")?.checked;
      const hiddenCompleted = row.dataset.completed === "true" && !checked;
      const matches = query === "" || (row.dataset.search || "").includes(query);
      const visible = matches && !hiddenCompleted;

      row.classList.toggle("hidden", !visible);
      if (visible) {
        visibleTeams.add(row.dataset.teamId);
        visibleCount += 1;
      }
    });

    this.teamHeadingTargets.forEach((heading) => {
      heading.classList.toggle("hidden", !visibleTeams.has(heading.dataset.teamId));
    });

    if (this.hasEmptyStateTarget) {
      this.emptyStateTarget.classList.toggle("hidden", visibleCount > 0);
    }
  }
}
