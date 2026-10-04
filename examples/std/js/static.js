// let state = ...
// const render_ui = ... (defined by base.js)

let global_state_string = localStorage.getItem("global-state")
if (global_state_string != null) {
  state.field0 = JSON.parse(global_state_string)
}
let ui = null

window.onload = () => {
  render_ui()
}
