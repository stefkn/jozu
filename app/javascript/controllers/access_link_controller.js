import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "status"]

  async copy() {
    try {
      await navigator.clipboard.writeText(this.inputTarget.value)
      this.statusTarget.textContent = "Link copied. Save it somewhere private."
    } catch {
      this.inputTarget.focus()
      this.inputTarget.select()
      this.statusTarget.textContent = "Select and copy the link above."
    }
  }
}
