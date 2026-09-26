import { Controller } from "@hotwired/stimulus"

// Progress tile dialog: tapping a kanji tile fetches its study-notes page
// (same content as the review "Study notes" pane) and shows it in a native
// <dialog>. Links still work as plain navigation when JS is off, with
// modifier keys, or if the fetch fails.
export default class extends Controller {
  static targets = ["dialog", "content", "fullPageLink"]

  async open(event) {
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
    if (event.button !== undefined && event.button !== 0) return

    const link = event.currentTarget
    if (!link || !link.href) return
    event.preventDefault()

    const url = link.href
    if (this.hasFullPageLinkTarget) this.fullPageLinkTarget.href = url
    this.contentTarget.innerHTML =
      '<p class="py-6 text-center text-sm text-zinc-500 dark:text-zinc-400">Loading study notes…</p>'
    if (!this.dialogTarget.open) this.dialogTarget.showModal()

    try {
      const response = await fetch(url, { headers: { Accept: "text/html" } })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      const html = await response.text()
      const doc = new DOMParser().parseFromString(html, "text/html")
      const card = doc.querySelector("[data-kanji-detail]")
      this.contentTarget.innerHTML = card ? card.outerHTML : html
    } catch {
      this.dialogTarget.close()
      window.location.href = url
    }
  }

  close() {
    this.dialogTarget.close()
  }

  backdrop(event) {
    if (event.target === this.dialogTarget) this.dialogTarget.close()
  }

  clear() {
    this.contentTarget.innerHTML = ""
  }
}
