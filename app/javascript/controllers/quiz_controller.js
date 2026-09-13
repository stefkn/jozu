import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["option", "answer", "responseTime", "confidenceRow"]

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
      if (option.dataset.correct === "true") {
        option.classList.add("border-green-500", "bg-green-50")
      } else if (option === selected) {
        option.classList.add("border-red-500", "bg-red-50")
      } else {
        option.classList.add("opacity-40")
      }
    })

    this.confidenceRowTarget.classList.remove("hidden")
  }
}