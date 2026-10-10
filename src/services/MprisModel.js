// Pure-JS MPRIS helpers shared by the bar widget, the audio panel's Now
// Playing card, and the standalone media card. Follows the MenuModel.js
// convention: no QML imports and no `.pragma library`, so node can require the
// file directly in test/mpris-model.js.
//
// Player selection is passed the engine's Stopped enum value rather than
// referencing the QML enum, which a pure module cannot see.

function pickPlayer(players, stoppedState) {
  const list = players || []
  for (let i = 0; i < list.length; i++)
    if (list[i] && list[i].isPlaying) return list[i]
  for (let j = 0; j < list.length; j++) {
    const p = list[j]
    if (p && p.canControl && p.playbackState !== stoppedState) return p
  }
  return list.length > 0 ? list[0] : null
}

function isShowable(player, stoppedState) {
  return !!player && String(player.trackTitle || "") !== "" && player.playbackState !== stoppedState
}

function fmtTime(sec) {
  const s = Math.floor(Number(sec))
  if (!Number.isFinite(s) || s < 0) return "0:00"
  const m = Math.floor(s / 60)
  const pad = s % 60 < 10 ? `0${s % 60}` : String(s % 60)
  return `${m}:${pad}`
}

function subtitleFor(player) {
  if (!player) return ""
  return [player.trackArtist, player.trackAlbum].filter(Boolean).join(" — ")
}

function progressFraction(player) {
  if (!player) return 0
  const len = Number(player.length || 0)
  if (!(len > 0)) return 0
  return Math.max(0, Math.min(1, Number(player.position || 0) / len))
}

// MPRIS seek takes microseconds relative to the current position, and every
// caller clicks on the same 0..1 fraction of a progress bar.
function seekOffset(player, fraction) {
  if (!player) return 0
  const len = Number(player.length || 0)
  if (!(len > 0)) return 0
  const target = Math.max(0, Math.min(1, Number(fraction))) * len
  return (target - Number(player.position || 0)) * 1e6
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    pickPlayer: pickPlayer,
    isShowable: isShowable,
    fmtTime: fmtTime,
    subtitleFor: subtitleFor,
    progressFraction: progressFraction,
    seekOffset: seekOffset
  }
}
