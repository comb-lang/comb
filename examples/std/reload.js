const parsed = new URL(window.location.href)
const protocol = parsed.protocol === "https:" ? "wss:" : "ws:"
const port = parsed.port ? `:${parsed.port}` : ""
const socket = new WebSocket(`${protocol}//${parsed.hostname}${port}${parsed.pathname}${parsed.search}`)
socket.addEventListener("message", (event) => {
  if (event.data === "reload") {
    location.reload()
  }
})
