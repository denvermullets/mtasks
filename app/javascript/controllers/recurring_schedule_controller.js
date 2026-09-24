import { Controller } from "@hotwired/stimulus";

// Shows only the schedule fields that apply to the chosen frequency on the recurring issue form.
export default class extends Controller {
  static targets = ["frequency", "weekly", "monthly", "unit"];

  connect() {
    this.update();
  }

  update() {
    const frequency = this.frequencyTarget.value;
    this.weeklyTarget.hidden = frequency !== "weekly";
    this.monthlyTarget.hidden = frequency !== "monthly";
    this.unitTarget.textContent = { daily: "day(s)", weekly: "week(s)", monthly: "month(s)" }[frequency];
  }
}
