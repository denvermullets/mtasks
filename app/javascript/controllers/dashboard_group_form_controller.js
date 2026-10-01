import { Controller } from "@hotwired/stimulus";

// Lives on the dashboard show page. One modal (dashboards/_group_form_modal) serves both
// "Add group" and "Edit group"; triggers pass url/method/title/submit/name/description/color/
// teamIds/projectIds/labelIds/allTeamIds/allProjectIds/deleteUrl as action params and open() fills the form from them.
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
    "label",
    "allTeam",
    "allProject",
    "teamSearch",
    "teamRow",
    "teamEmptyState",
    "projectSearch",
    "projectRow",
    "teamHeading",
    "emptyState",
    "labelSearch",
    "labelRow",
    "labelHeading",
    "labelEmptyState",
    "deleteSection",
    "deleteForm",
    "errors",
  ];

  connect() {
    this.boundHandleEscape = this.handleEscape.bind(this);
    // The server re-rendered the modal open after a 422: wire Escape + focus as if the user opened it.
    if (this.hasModalTarget && !this.modalTarget.classList.contains("hidden")) {
      this.applyAllVisibility();
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
      labelIds = [],
      allTeamIds = [],
      allProjectIds = [],
      deleteUrl = "",
    } = event.params;

    // Triggers outside the dashboard_content frame pass a bare URL (their rendered query would go
    // stale after a tab switch), so carry over the current view's filter/mine/q/team from the address bar.
    this.formTarget.action = url.includes("?") ? url : url + window.location.search;
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
    this.labelTargets.forEach((box) => {
      box.checked = labelIds.includes(Number(box.value));
    });
    this.allTeamTargets.forEach((box) => {
      box.checked = allTeamIds.includes(Number(box.value));
    });
    this.allProjectTargets.forEach((box) => {
      box.checked = allProjectIds.includes(Number(box.value));
    });
    this.searchTargets().forEach((input) => {
      input.value = "";
    });
    this.applyAllVisibility();

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

  // Projects are usually tracked as a whole, so ticking one turns on its "All issues" toggle.
  // Only a user's click does this; open() restores saved groups exactly as they were.
  projectToggled(event) {
    const box = event.target;
    if (!box.checked) return;

    const all = box.closest("[data-dashboard-group-form-target~='projectRow']")
      ?.querySelector("[data-dashboard-group-form-target~='allProject']");
    if (all) all.checked = true;
  }

  // Teams and labels have no search box when their list is empty, so collect whichever exist.
  searchTargets() {
    return [
      this.hasTeamSearchTarget && this.teamSearchTarget,
      this.projectSearchTarget,
      this.hasLabelSearchTarget && this.labelSearchTarget,
    ].filter(Boolean);
  }

  query(input) {
    return input ? input.value.trim().toLowerCase() : "";
  }

  matches(row, query) {
    return query === "" || (row.dataset.search || "").includes(query);
  }

  applyAllVisibility() {
    this.applyTeamVisibility();
    this.applyProjectVisibility();
    this.applyLabelVisibility();
  }

  applyTeamVisibility() {
    const query = this.query(this.hasTeamSearchTarget && this.teamSearchTarget);
    let visibleCount = 0;

    this.teamRowTargets.forEach((row) => {
      const visible = this.matches(row, query);
      row.classList.toggle("hidden", !visible);
      if (visible) visibleCount += 1;
    });

    if (this.hasTeamEmptyStateTarget) {
      this.teamEmptyStateTarget.classList.toggle("hidden", visibleCount > 0);
    }
  }

  // A project row shows when it matches the filter text and is either still open or currently
  // checked (completed projects only stay listed so they can be unchecked). Team headings
  // follow their rows.
  applyProjectVisibility() {
    const query = this.query(this.projectSearchTarget);
    const visibleTeams = new Set();
    let visibleCount = 0;

    this.projectRowTargets.forEach((row) => {
      const checked = row.querySelector("[data-source]")?.checked;
      const hiddenCompleted = row.dataset.completed === "true" && !checked;
      const visible = this.matches(row, query) && !hiddenCompleted;

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

  // Labels are team-scoped, so once any team or project is ticked only labels from those teams
  // show. Nothing ticked shows every label (labels alone is a valid group). A checked label from
  // another team stays listed so it can be unchecked. The filter text applies on top of both.
  applyLabelVisibility() {
    const query = this.query(this.hasLabelSearchTarget && this.labelSearchTarget);
    const teamIds = new Set();
    this.teamTargets.forEach((box) => {
      if (box.checked) teamIds.add(box.value);
    });
    this.projectTargets.forEach((box) => {
      if (box.checked) teamIds.add(box.closest("[data-team-id]").dataset.teamId);
    });

    const visibleTeams = new Set();
    let visibleCount = 0;

    this.labelRowTargets.forEach((row) => {
      const checked = row.querySelector("input[type=checkbox]")?.checked;
      const inTeams = teamIds.size === 0 || teamIds.has(row.dataset.teamId) || checked;
      const visible = inTeams && this.matches(row, query);

      row.classList.toggle("hidden", !visible);
      if (visible) {
        visibleTeams.add(row.dataset.teamId);
        visibleCount += 1;
      }
    });

    this.labelHeadingTargets.forEach((heading) => {
      heading.classList.toggle("hidden", !visibleTeams.has(heading.dataset.teamId));
    });

    if (this.hasLabelEmptyStateTarget) {
      this.labelEmptyStateTarget.classList.toggle("hidden", visibleCount > 0);
    }
  }
}
