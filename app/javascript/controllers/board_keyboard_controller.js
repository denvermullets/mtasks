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

    // Press 'M' to open milestone picker on hovered card
    if (event.key === "m" || event.key === "M") {
      event.preventDefault();
      this.openMilestonePicker();
    }

    // Press 'S' to open lane picker on hovered card
    if (event.key === "s" || event.key === "S") {
      event.preventDefault();
      this.openLanePicker();
    }

    // Press 'P' to open project picker on hovered card
    if (event.key === "p" || event.key === "P") {
      event.preventDefault();
      this.openProjectPicker();
    }
  }

  openLabelPicker() {
    // Find the currently hovered card
    const hoveredCard = document.querySelector('[data-hovered="true"]');
    if (!hoveredCard) {
      return;
    }

    // Find the label picker inside the hovered card
    const labelPicker = hoveredCard.querySelector('[data-controller="label-picker"]');
    if (!labelPicker) {
      return;
    }

    // Get the label picker controller and open it
    const controller = this.application.getControllerForElementAndIdentifier(
      labelPicker,
      "label-picker"
    );
    if (controller && controller.open) {
      controller.open();
    }
  }

  openMilestonePicker() {
    // Find the currently hovered card
    const hoveredCard = document.querySelector('[data-hovered="true"]');
    if (!hoveredCard) {
      return;
    }

    // Find the milestone picker inside the hovered card
    const milestonePicker = hoveredCard.querySelector('[data-controller="milestone-picker"]');
    if (!milestonePicker) {
      return;
    }

    // Get the milestone picker controller and open it
    const controller = this.application.getControllerForElementAndIdentifier(
      milestonePicker,
      "milestone-picker"
    );
    if (controller && controller.open) {
      controller.open();
    }
  }

  openLanePicker() {
    // Find the currently hovered card
    const hoveredCard = document.querySelector('[data-hovered="true"]');
    if (!hoveredCard) {
      return;
    }

    // Find the lane picker inside the hovered card
    const lanePicker = hoveredCard.querySelector('[data-controller="lane-picker"]');
    if (!lanePicker) {
      return;
    }

    // Get the lane picker controller and open it
    const controller = this.application.getControllerForElementAndIdentifier(
      lanePicker,
      "lane-picker"
    );
    if (controller && controller.open) {
      controller.open();
    }
  }

  openProjectPicker() {
    // Find the currently hovered card
    const hoveredCard = document.querySelector('[data-hovered="true"]');
    if (!hoveredCard) {
      return;
    }

    // Find the project picker inside the hovered card
    const projectPicker = hoveredCard.querySelector('[data-controller="project-picker"]');
    if (!projectPicker) {
      return;
    }

    // Get the project picker controller and open it
    const controller = this.application.getControllerForElementAndIdentifier(
      projectPicker,
      "project-picker"
    );
    if (controller && controller.open) {
      controller.open();
    }
  }

  createNewIssue() {
    // Get the team ID from the URL path
    const pathParts = window.location.pathname.split("/");
    const teamIndex = pathParts.indexOf("teams");
    if (teamIndex !== -1 && pathParts[teamIndex + 1]) {
      const teamId = pathParts[teamIndex + 1];
      window.location.href = `/teams/${teamId}/issues/new`;
    } else {
      console.error("Could not determine team ID from URL");
    }
  }
}
