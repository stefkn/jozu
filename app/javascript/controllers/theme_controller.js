import { Controller } from "@hotwired/stimulus"

// Header dark-mode toggle + Settings theme radios share this controller.
// Theme resolution order: localStorage ("jozu-theme") > server default
// (<html data-server-theme>) > "system". The `dark` class lives on
// <html> (see @custom-variant in application.css). Choices persist to
// localStorage immediately and sync to User#settings via PATCH /settings
// so the preference follows the learner across devices.
export default class extends Controller {
  static targets = ["toggle"]
  static values = { csrf: String }

  connect() {
    this.media = window.matchMedia("(prefers-color-scheme: dark)")
    this.systemListener = () => {
      if (this.currentTheme() === "system") this.render(this.currentTheme())
    }
    this.media.addEventListener?.("change", this.systemListener)
    this.render(this.currentTheme())
  }

  disconnect() {
    this.media?.removeEventListener?.("change", this.systemListener)
  }

  // Header button: flip between explicit light/dark.
  toggle(event) {
    event?.preventDefault()
    const isDark = document.documentElement.classList.contains("dark")
    this.save(isDark ? "light" : "dark")
  }

  // Settings radios: <input data-action="change->theme#choose" value="system|light|dark">
  choose(event) {
    this.save(event.currentTarget.value)
  }

  currentTheme() {
    try {
      return (
        localStorage.getItem("jozu-theme") ||
        document.documentElement.dataset.serverTheme ||
        "system"
      )
    } catch {
      return document.documentElement.dataset.serverTheme || "system"
    }
  }

  isDark(theme) {
    if (theme === "dark") return true
    if (theme === "light") return false
    return this.media?.matches ?? false
  }

  render(theme) {
    const dark = this.isDark(theme)
    document.documentElement.classList.toggle("dark", dark)
    document.documentElement.style.colorScheme = dark ? "dark" : "light"
    const meta = document.querySelector('meta[name="theme-color"]')
    if (meta) meta.setAttribute("content", dark ? "#09090b" : "#fafafa")
  }

  save(theme) {
    if (!["system", "light", "dark"].includes(theme)) return
    try {
      localStorage.setItem("jozu-theme", theme)
    } catch {
      // private mode etc. — server sync still applies for this session
    }
    this.render(theme)
    this.syncServer(theme)
  }

  syncServer(theme) {
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    if (!token) return
    // Theme-only sync: the server leaves skip_number_kanji/practice_mode
    // untouched (see SettingsController#update). The full form submit on
    // Save persists everything together.
    const body = new URLSearchParams()
    body.append("theme", theme)
    body.append("theme_only", "1")
    fetch("/settings", {
      method: "PATCH",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        "X-CSRF-Token": token,
        Accept: "application/json",
      },
      body: body.toString(),
    }).catch(() => {})
  }
}
