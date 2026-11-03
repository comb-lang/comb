let state = {}

function fetch_code() {
  return fetch(window.location.href + "code.js").then(response => {
    if (!response.ok) {
      throw new Error(`Failed to fetch (status ${response.status})`)
    }
    return response.text()
  }).then(code => {
    window.code = new Function(code + "; return {serialize_state, deserialize_state, initial_state, render_ui}")()
  })
}

// Handle initial code
fetch_code().then(() => {
  state.field0 = window.code.deserialize_state("")
  let global_state_string = localStorage.getItem("global-state")
  if (global_state_string != null) {
    state.field1 = JSON.parse(global_state_string)
  } else {
    state.field1 = initial_state.field1
  }
  window.code.render_ui()
})

// Listen for reload
const parsed = new URL(window.location.href)
const protocol = parsed.protocol === "https:" ? "wss:" : "ws:"
const port = parsed.port ? `:${parsed.port}` : ""
const socket = new WebSocket(`${protocol}//${parsed.hostname}${port}${parsed.pathname}${parsed.search}`)
socket.addEventListener("message", (event) => {
  if (event.data === "reload") {
    const serialized = window.code.serialize_state(state.field0)
    fetch_code().then(() => {
      state.field0 = window.code.deserialize_state(serialized)
      window.code.render_ui()
    })
  }
})
