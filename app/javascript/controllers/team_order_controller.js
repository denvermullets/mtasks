import { Controller } from "@hotwired/stimulus";
import Sortable from "sortablejs";

// Drag-and-drop layout of sidebar teams: reorder groups, reorder teams, and move teams in and out of
// groups. Every change saves the whole layout. Owned and joined teams can share a group, but an
// ungrouped team can only return to its own section.
export default class extends Controller {
  static targets = ["list", "groups"];
  static values = { url: String };

  connect() {
    this.csrfToken = document.querySelector('meta[name="csrf-token"]')?.content;
    this.sortables = this.listTargets.map((list) =>
      Sortable.create(list, {
        animation: 150,
        group: {
          name: "sidebar-teams",
          put: (to, _from, dragEl) => {
            const kind = to.el.dataset.kind;
            return kind === "group" || kind === dragEl.dataset.scope;
          },
        },
        onEnd: () => this.save(),
      })
    );
    if (this.hasGroupsTarget) {
      this.sortables.push(
        Sortable.create(this.groupsTarget, {
          animation: 150,
          handle: "[data-group-handle]",
          draggable: "[data-group-id]",
          onEnd: () => this.save(),
        })
      );
    }
  }

  disconnect() {
    this.sortables?.forEach((sortable) => sortable.destroy());
    this.sortables = [];
  }

  rename(event) {
    event.target.form.requestSubmit();
  }

  teamIds(list) {
    return list
      ? Array.from(list.querySelectorAll("[data-team-id]")).map((el) => Number(el.dataset.teamId))
      : [];
  }

  async save() {
    const groups = this.hasGroupsTarget
      ? Array.from(this.groupsTarget.querySelectorAll("[data-group-id]")).map((group) => ({
          id: group.dataset.groupId,
          team_ids: this.teamIds(group.querySelector('[data-kind="group"]')),
        }))
      : [];
    const body = {
      groups,
      owned: this.teamIds(this.element.querySelector('[data-kind="owned"]')),
      joined: this.teamIds(this.element.querySelector('[data-kind="joined"]')),
    };

    try {
      const response = await fetch(this.urlValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          Accept: "text/vnd.turbo-stream.html",
          "X-CSRF-Token": this.csrfToken,
        },
        body: JSON.stringify(body),
      });
      if (response.ok) {
        const html = await response.text();
        window.Turbo.renderStreamMessage(html);
      } else {
        console.error("Failed to save team order", response.status);
      }
    } catch (error) {
      console.error("Error saving team order:", error);
    }
  }
}
