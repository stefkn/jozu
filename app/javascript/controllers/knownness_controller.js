import { Controller } from "@hotwired/stimulus"

// Explicit spoken-word labeling ("Do you say this word?"). POSTs via fetch so
// the surrounding quiz turbo-frame is untouched; shows a confirmation inline.
export default class extends Controller {
  static targets = ["button", "confirmation"]
  static values = { wordId: Number }

  async mark(event) {
    const level = event.currentTarget.dataset.level
    if (!level || this.element.dataset.saved) return

    this.buttonTargets.forEach((b) => { b.disabled = true; b.classList.add("opacity-40") })
    event.currentTarget.classList.remove("opacity-40")

    try {
      const token = document.querySelector('meta[name="csrf-token"]')?.content
      const response = await fetch("/knownness", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          ...(token ? { "X-CSRF-Token": token } : {})
        },
        body: JSON.stringify({ word_id: this.wordIdValue, level })
      })
      if (response.ok) {
        this.element.dataset.saved = "true"
        this.confirmationTarget.classList.remove("hidden")
      } else {
        this.buttonTargets.forEach((b) => { b.disabled = false; b.classList.remove("opacity-40") })
      }
    } catch (_e) {
      this.buttonTargets.forEach((b) => { b.disabled = false; b.classList.remove("opacity-40") })
    }
  }
}
