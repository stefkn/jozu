import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["option", "answer", "responseTime", "confidenceRow", "details"]

  connect() {
    this.presentedAt = Number(this.element.dataset.quizPresentedAt) || Date.now()
  }

  select(event) {
    if (this.element.dataset.answered) return
    this.element.dataset.answered = "true"

    const selected = event.currentTarget
    this.answerTarget.value = selected.dataset.answer
    this.responseTimeTarget.value = Date.now() - this.presentedAt

    this.optionTargets.forEach((option) => {
      option.disabled = true
      const dark = document.documentElement.classList.contains("dark")
      if (option.dataset.correct === "true") {
        option.style.borderColor = "var(--color-green-500)"
        option.style.backgroundColor = dark ? "var(--color-green-950)" : "var(--color-green-50)"
      } else if (option === selected) {
        option.style.borderColor = "var(--color-red-500)"
        option.style.backgroundColor = dark ? "var(--color-red-950)" : "var(--color-red-50)"
      } else {
        option.classList.add("opacity-40")
      }
    })

    this.confidenceRowTarget.classList.remove("hidden")
    if (this.hasDetailsTarget) this.detailsTarget.classList.remove("hidden")
  }
}