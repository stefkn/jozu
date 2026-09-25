import { Controller } from "@hotwired/stimulus"

// Tap-to-reveal furigana + English definitions for kanji in the sentence prompt.
// Furigana is hidden by default (recall practice); tapping a word shows a bubble
// with its reading (data-reading) and English meaning (data-meaning). The
// blanked target is also tappable and reveals its meaning as a hint.
export default class extends Controller {
  static targets = ["bubble"]

  toggle(event) {
    const span = event.target.closest(".kanji-tap")
    if (!span || span === this.active) {
      this.hide()
      return
    }
    this.show(span)
  }

  show(span) {
    const parts = []
    if (span.dataset.reading) parts.push(span.dataset.reading)
    if (span.dataset.meaning) parts.push(span.dataset.meaning)
    this.bubbleTarget.textContent = parts.join(" · ")
    const rect = span.getBoundingClientRect()
    this.bubbleTarget.style.left = `${rect.left + rect.width / 2}px`
    this.bubbleTarget.style.top = `${Math.max(8, rect.top - 8)}px`
    this.bubbleTarget.classList.add("visible")
    this.active = span
  }

  hide() {
    this.bubbleTarget.classList.remove("visible")
    this.active = null
  }
}