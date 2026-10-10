const assert = require('node:assert')
const M = require('../src/services/UsbStorageModel.js')

function drive(overrides) {
  return Object.assign({
    name: 'sda',
    path: '/dev/sda',
    size: 31000000000,
    vendor: 'SanDisk',
    model: 'Ultra Fit',
    serial: '4C530001230930107151',
    removable: true,
    usb: { speed: 5000, version: '3.20', manufacturer: 'SanDisk', product: 'Ultra Fit', port: '2-1' },
    partitions: [{
      name: 'sda1',
      path: '/dev/sda1',
      fstype: 'exfat',
      uuid: '1234-ABCD',
      label: 'EFIUSB',
      mountpoint: '/run/media/cwebb/EFIUSB',
      size: 30999000000,
      used: 8000000000,
      avail: 22999000000
    }]
  }, overrides || {})
}

assert.strictEqual(M.formatBytes(0), '0 B', 'zero is 0 B')
assert.strictEqual(M.formatBytes(null), '0 B', 'null is 0 B')
assert.strictEqual(M.formatBytes(31000000000), '31.0 GB', 'decimal units, one decimal below 100')
assert.strictEqual(M.formatBytes(480000000), '480 MB', 'whole number at or above 100')
assert.strictEqual(M.formatBytes(1.5e12), '1.5 TB', 'TB is the largest unit')

// parseDrives reports malformed JSON, so capture the diagnostic: assert it
// fires, and keep a passing run's output clean.
const logged = []
const realError = console.error
console.error = function() { logged.push(Array.prototype.slice.call(arguments).join(' ')) }
assert.deepStrictEqual(M.parseDrives(''), [], 'empty input is an empty list')
assert.deepStrictEqual(M.parseDrives('   '), [], 'blank input is an empty list')
assert.deepStrictEqual(M.parseDrives('not json'), [], 'invalid JSON degrades to an empty list')
assert.deepStrictEqual(M.parseDrives('{"a":1}'), [], 'a non-array degrades to an empty list')
console.error = realError
assert.strictEqual(logged.length, 1, 'malformed JSON is reported exactly once')
assert.ok(logged[0].indexOf('usb-storage list parse failed') === 0, 'the diagnostic names the source')
assert.strictEqual(M.parseDrives(JSON.stringify([drive()])).length, 1, 'a valid array parses')

const mounted = drive()
assert.strictEqual(M.primaryPartition(mounted).name, 'sda1', 'the mounted partition wins')
const twoParts = drive({
  partitions: [
    { name: 'sda1', label: '', mountpoint: '', used: 1, size: 10 },
    { name: 'sda2', label: 'DATA', mountpoint: '/mnt/data', used: 5, size: 10 }
  ]
})
assert.strictEqual(M.primaryPartition(twoParts).name, 'sda2', 'an unmounted partition does not win')
assert.strictEqual(M.primaryPartition(drive({ partitions: [] })), null, 'no partitions is null')

assert.strictEqual(M.driveTitle(mounted), 'EFIUSB', 'the volume label titles the drive')
assert.strictEqual(M.driveTitle(drive({ partitions: [] })), '31.0 GB USB Drive', 'no label falls back to capacity')
assert.strictEqual(M.driveTitle(drive({ partitions: [{ name: 'sda1', label: '', mountpoint: '' }] })),
  '31.0 GB USB Drive', 'a blank label falls back to capacity')

assert.strictEqual(M.driveSubtitle(mounted), 'SanDisk Ultra Fit', 'identity comes from the USB descriptor')
assert.strictEqual(M.driveSubtitle(drive({ usb: { manufacturer: 'USB', product: 'USB' }, vendor: 'USB', model: 'USB' })),
  'USB', 'repeated identity words collapse to one')
assert.strictEqual(M.driveSubtitle(drive({ usb: {} })), 'SanDisk Ultra Fit',
  'the SCSI inquiry strings fill in when there is no USB descriptor')

assert.strictEqual(M.speedLabel(5000), 'USB 3.2 Gen 1 · 5 Gbps', 'a known link speed is named')
assert.strictEqual(M.speedLabel(480), 'USB 2.0 · 480 Mbps', 'a USB 2 link is named')
assert.strictEqual(M.speedLabel(1500), '1500 Mbps', 'an unknown speed still prints')
assert.strictEqual(M.speedLabel(0), 'Unknown', 'no speed is Unknown')

assert.strictEqual(M.runningSlow(drive({ usb: { speed: 480, version: '3.20' } })), true,
  'a USB 3 device on a USB 2 link is flagged')
assert.strictEqual(M.runningSlow(drive({ usb: { speed: 5000, version: '3.20' } })), false,
  'a USB 3 device on a USB 3 link is not flagged')
assert.strictEqual(M.runningSlow(drive({ usb: { speed: 480, version: '2.10' } })), false,
  'a genuine USB 2 device is not flagged')
assert.strictEqual(M.runningSlow(drive({ usb: { speed: 0, version: '3.20' } })), false,
  'an unknown link speed is not flagged')

assert.strictEqual(M.fsLabel('vfat'), 'FAT32', 'friendly filesystem names win')
assert.strictEqual(M.fsLabel('zfs'), 'zfs', 'an unmapped filesystem prints its raw name')
assert.strictEqual(M.fsLabel(null), '—', 'no filesystem is a dash')

const part = M.primaryPartition(mounted)
assert.ok(Math.abs(M.usedFraction(part) - 0.258) < 0.01, 'usedFraction reports used/size')
assert.strictEqual(M.usedFraction(null), 0, 'no partition is zero')
assert.strictEqual(M.usedFraction({ size: 100, used: null }), 0, 'unknown usage is zero')
assert.strictEqual(M.usedFraction({ size: 100, used: 250 }), 1, 'over-full clamps to 1')

console.log('usb-storage-model: OK')
