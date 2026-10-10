const assert = require('node:assert')
const M = require('../src/services/MprisModel.js')

const STOPPED = 0
const PLAYING = 1
const PAUSED = 2

function player(overrides) {
  return Object.assign({
    isPlaying: false,
    canControl: true,
    playbackState: PAUSED,
    trackTitle: 'Track',
    trackArtist: 'Artist',
    trackAlbum: 'Album',
    trackArtUrl: '',
    position: 30,
    length: 120,
    canGoPrevious: true,
    canGoNext: true,
    canTogglePlaying: true
  }, overrides || {})
}

assert.strictEqual(M.pickPlayer([], STOPPED), null, 'no players is null')
assert.strictEqual(M.pickPlayer(null, STOPPED), null, 'a null list is null')

const playing = player({ isPlaying: true, trackTitle: 'Playing' })
const paused = player({ trackTitle: 'Paused' })
assert.strictEqual(M.pickPlayer([paused, playing], STOPPED).trackTitle, 'Playing',
  'the playing player wins over a paused one')
assert.strictEqual(M.pickPlayer([player({ playbackState: STOPPED, trackTitle: 'Stopped' }), paused], STOPPED).trackTitle,
  'Paused', 'a stopped player loses to a controllable one')
assert.strictEqual(M.pickPlayer([player({ playbackState: STOPPED, trackTitle: 'Stopped' })], STOPPED).trackTitle,
  'Stopped', 'an all-stopped list still yields a player')
assert.strictEqual(M.pickPlayer([player({ playbackState: STOPPED, trackTitle: 'Uncontrollable', canControl: false }),
  playing], STOPPED).trackTitle, 'Playing', 'a playing player beats an uncontrollable one')
assert.strictEqual(M.pickPlayer([player({ playbackState: STOPPED, trackTitle: 'Only' })], STOPPED).trackTitle,
  'Only', 'a single stopped player is still returned')

assert.strictEqual(M.isShowable(null, STOPPED), false, 'a missing player is not showable')
assert.strictEqual(M.isShowable(player({ playbackState: STOPPED }), STOPPED), false,
  'a stopped player is not showable')
assert.strictEqual(M.isShowable(player({ trackTitle: '' }), PLAYING), false,
  'a titleless player is not showable')
assert.strictEqual(M.isShowable(player({ trackTitle: 'T', playbackState: PLAYING }), STOPPED), true,
  'a playing player with a title is showable')
assert.strictEqual(M.isShowable(player({ trackTitle: 'T', playbackState: PAUSED }), STOPPED), true,
  'a paused player with a title is showable')

assert.strictEqual(M.fmtTime(0), '0:00', 'zero seconds')
assert.strictEqual(M.fmtTime(65), '1:05', 'seconds are zero-padded')
assert.strictEqual(M.fmtTime(59), '0:59', 'under a minute')
assert.strictEqual(M.fmtTime(3599), '59:59', 'minutes are not capped at 60')
assert.strictEqual(M.fmtTime(-1), '0:00', 'a negative position reads 0:00')
assert.strictEqual(M.fmtTime(null), '0:00', 'null reads 0:00')
assert.strictEqual(M.fmtTime(undefined), '0:00', 'undefined reads 0:00')
assert.strictEqual(M.fmtTime(Infinity), '0:00', 'a non-finite position reads 0:00')

assert.strictEqual(M.subtitleFor(player()), 'Artist — Album', 'artist and album are joined')
assert.strictEqual(M.subtitleFor(player({ trackAlbum: '' })), 'Artist', 'a missing album is dropped')
assert.strictEqual(M.subtitleFor(player({ trackArtist: '' })), 'Album', 'a missing artist is dropped')
assert.strictEqual(M.subtitleFor(player({ trackArtist: '', trackAlbum: '' })), '',
  'neither reads as empty')
assert.strictEqual(M.subtitleFor(null), '', 'no player reads as empty')

assert.strictEqual(M.progressFraction(player({ position: 30, length: 120 })), 0.25, 'a quarter through')
assert.strictEqual(M.progressFraction(player({ position: 0, length: 0 })), 0, 'an unknown length is zero')
assert.strictEqual(M.progressFraction(player({ position: 200, length: 120 })), 1, 'past the end clamps to 1')
assert.strictEqual(M.progressFraction(player({ position: -5, length: 120 })), 0, 'negative clamps to 0')
assert.strictEqual(M.progressFraction(null), 0, 'no player is zero')

assert.strictEqual(M.seekOffset(player({ position: 30, length: 120 }), 0.5), 30000000,
  'seeking to the midpoint offsets by the remaining microseconds')
assert.strictEqual(M.seekOffset(player({ position: 30, length: 120 }), 0), -30000000,
  'seeking to the start rewinds')
assert.strictEqual(M.seekOffset(player({ position: 30, length: 120 }), 2), 90000000,
  'a fraction past 1 clamps to the end')
assert.strictEqual(M.seekOffset(player({ position: 30, length: 0 }), 0.5), 0, 'an unknown length cannot seek')
assert.strictEqual(M.seekOffset(null, 0.5), 0, 'no player cannot seek')

console.log('mpris-model: OK')
