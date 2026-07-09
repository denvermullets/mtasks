import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  connect() {
    this.boundHandleKeyPress = this.handleKeyPress.bind(this);
    document.addEventListener("keydown", this.boundHandleKeyPress);
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundHandleKeyPress);
  }

  handleKeyPress(event) {
    // Ignore if user is typing in an input field
    if (event.target.matches("input, textarea, select")) {
      return;
    }

    // An open picker owns the keyboard — it binds its own arrows, enter and escape.
    // Reopening it here would retarget it at whatever card the mouse drifted over.
    if (document.querySelector("[data-shared-picker]:not(.hidden)")) {
      return;
    }

    // Press 'C' to create new issue
    if (event.key === "c" || event.key === "C") {
      event.preventDefault();
      this.createNewIssue();
    }

    // Press 'L' to open label picker on hovered card
    if (event.key === "l" || event.key === "L") {
      event.preventDefault();
      this.openLabelPicker();
    }

    // Press 'S' to open lane picker on hovered card
    if (event.key === "s" || event.key === "S") {
      event.preventDefault();
      this.openLanePicker();
    }

    // Press 'J' to open project picker on hovered card
    if (event.key === "j" || event.key === "J") {
      event.preventDefault();
      this.openProjectPicker();
    }

    // Press 'P' to open priority picker on hovered card
    if (event.key === "p" || event.key === "P") {
      event.preventDefault();
      this.openPriorityPicker();
    }
  }

  openPriorityPicker() {
    const hoveredCard = document.querySelector('[data-hovered="true"]');
    if (!hoveredCard) {
      return;
    }

    const priorityPicker = document.querySelector('[data-shared-picker="priority"]');
    if (!priorityPicker) {
      return;
    }

    const controller = this.application.getControllerForElementAndIdentifier(
      priorityPicker,
      "priority-picker"
    );
    if (controller && controller.openForCard) {
      controller.openForCard(hoveredCard);
    }
  }

  openLabelPicker() {
    // Find the currently hovered card
    const hoveredCard = document.querySelector('[data-hovered="true"]');
    if (!hoveredCard) {
      return;
    }

    // Open the single shared label picker, retargeted at the hovered card
    const labelPicker = document.querySelector('[data-shared-picker="label"]');
    if (!labelPicker) {
      return;
    }

    const controller = this.application.getControllerForElementAndIdentifier(
      labelPicker,
      "label-picker"
    );
    if (controller && controller.openForCard) {
      controller.openForCard(hoveredCard);
    }
  }

  openLanePicker() {
    // Find the currently hovered card
    const hoveredCard = document.querySelector('[data-hovered="true"]');
    if (!hoveredCard) {
      return;
    }

    // Open the single shared lane picker, retargeted at the hovered card
    const lanePicker = document.querySelector('[data-shared-picker="lane"]');
    if (!lanePicker) {
      return;
    }

    const controller = this.application.getControllerForElementAndIdentifier(
      lanePicker,
      "lane-picker"
    );
    if (controller && controller.openForCard) {
      controller.openForCard(hoveredCard);
    }
  }

  openProjectPicker() {
    // Find the currently hovered card
    const hoveredCard = document.querySelector('[data-hovered="true"]');
    if (!hoveredCard) {
      return;
    }

    // Open the single shared project picker, retargeted at the hovered card
    const projectPicker = document.querySelector('[data-shared-picker="project"]');
    if (!projectPicker) {
      return;
    }

    const controller = this.application.getControllerForElementAndIdentifier(
      projectPicker,
      "project-picker"
    );
    if (controller && controller.openForCard) {
      controller.openForCard(hoveredCard);
    }
  }

  createNewIssue() {
    // Get the team ID from the URL path
    const pathParts = window.location.pathname.split("/");
    const teamIndex = pathParts.indexOf("teams");
    if (teamIndex !== -1 && pathParts[teamIndex + 1]) {
      const teamId = pathParts[teamIndex + 1];
      let url = `/teams/${teamId}/issues/new`;

      // If on a project page, pre-select the project
      const projectIndex = pathParts.indexOf("projects");
      if (projectIndex !== -1 && pathParts[projectIndex + 1]) {
        url += `?project_id=${pathParts[projectIndex + 1]}`;
      }

      window.location.href = url;
    } else {
      console.error("Could not determine team ID from URL");
    }
  }
}
