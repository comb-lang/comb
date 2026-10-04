let state = {}

function fetch_code() {
  return fetch(window.location.href + "code.js").then(response => {
    if (!response.ok) {
      throw new Error(`Failed to fetch (status ${response.status})`)
    }
    return response.text()
  }).then(code => {
    return new Function(code + "; return {state_from_serialized, render_ui, initial_global_state}")()
  })
}

// Handle initial code
fetch_code().then(c => {
  state.field1 = c.state_from_serialized("")
  let global_state_string = localStorage.getItem("global-state")
  if (global_state_string != null) {
    state.field0 = JSON.parse(global_state_string)
  } else {
    state.field0 = initial_global_state
  }
  c.render_ui()
})

// Listen for reload
const parsed = new URL(window.location.href)
const protocol = parsed.protocol === "https:" ? "wss:" : "ws:"
const port = parsed.port ? `:${parsed.port}` : ""
const socket = new WebSocket(`${protocol}//${parsed.hostname}${port}${parsed.pathname}${parsed.search}`)
socket.addEventListener("message", (event) => {
  if (event.data === "reload") {
    const serialized = state.field1.field1()
    fetch_code().then(c => {
      state.field1 = c.state_from_serialized(serialized)
      c.render_ui()
    })
  }
})
