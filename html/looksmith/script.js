(() => {
  const overlay = document.getElementById('nuiOverlay')
  const app = document.getElementById('app')
  const keysList = document.getElementById('keysList')
  const costEl = document.getElementById('cost')
  const closeBtn = document.getElementById('closeBtn')

  window.currentPlayers = []

  function show() { overlay.classList.remove('hidden') }
  function hide() { overlay.classList.add('hidden') }

  closeBtn && closeBtn.addEventListener('click', () => fetch(`https://${GetParentResourceName()}/close`, { method:'POST', body: JSON.stringify({}) }))

  window.addEventListener('message', (ev) => {
    const d = ev.data
    if (!d) return
    if (d.action === 'open') {
      costEl.textContent = d.cost || 0
      window.currentPlayers = d.players || []
      renderKeys(d.keys || [])
      show()
    } else if (d.action === 'close') {
      hide()
    } else if (d.action === 'updateKeys') {
      window.currentPlayers = d.players || window.currentPlayers || []
      renderKeys(d.keys || [])
    }
  })

  function renderKeys(keys) {
    keysList.innerHTML = ''
    if (!keys || keys.length === 0) { keysList.innerHTML = '<div class="keyItem"><div class="keyLeft"><div class="keyPlate">Keine Schlüssel gefunden</div></div></div>'; return }
    keys.forEach(k => {
      const node = document.createElement('div'); node.className = 'keyItem'
      let playersHtml = '<select class="playerSelect">'
      if (!window.currentPlayers || window.currentPlayers.length === 0) playersHtml += '<option value="">Kein Spieler in Reichweite</option>'
      else {
        playersHtml += '<option value="">-- Spieler wählen --</option>'
        window.currentPlayers.forEach(p => { playersHtml += `<option value="${p.serverId}">${escapeHtml(p.serverId)} · ${escapeHtml(p.name)} · ${p.distance}m</option>` })
      }
      playersHtml += '</select>'

      node.innerHTML = `
        <div class="keyLeft">
          <div>
            <div class="keyPlate">${escapeHtml(k.plate)}</div>
            <div class="keyLabel">${escapeHtml(k.label)}</div>
          </div>
        </div>
        <div class="keyActions">
          <button class="smallBtn dupBtn" data-id="${escapeHtml(k.key_id)}">Duplizieren</button>
          ${playersHtml}
          <button class="smallBtn giveBtn" data-id="${escapeHtml(k.key_id)}">Übergeben</button>
        </div>
      `
      keysList.appendChild(node)
    })

    document.querySelectorAll('.dupBtn').forEach(btn => btn.addEventListener('click', () => {
      const id = btn.getAttribute('data-id'); fetch(`https://${GetParentResourceName()}/duplicate`, { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ key_id: id }) })
    }))

    document.querySelectorAll('.giveBtn').forEach(btn => btn.addEventListener('click', (ev) => {
      const id = btn.getAttribute('data-id')
      const sel = btn.parentElement.querySelector('.playerSelect')
      const target = sel ? sel.value : ''
      const payload = target && target !== '' ? { key_id: id, targetServerId: Number(target) } : { key_id: id }
      fetch(`https://${GetParentResourceName()}/give`, { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify(payload) })
    }))
  }

  function escapeHtml(text) {
    if (text === null || text === undefined) return ''
    return String(text).replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/"/g,"&quot;")
  }
})()