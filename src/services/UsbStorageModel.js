// Pure-JS formatting helpers for the USB popup. Follows the MenuModel.js
// convention: no QML imports and no `.pragma library`, so node can require the
// file directly in test/usb-storage-model.js.
//
// runningSlow() encodes the useful field heuristic: a USB 3 device that
// negotiated a USB 2 link is almost always a half-seated plug, a USB 2 hub, or
// a USB 2 extension cable.

const BYTE_UNITS = ["B", "KB", "MB", "GB", "TB"]

const FS_NAMES = {
  vfat: "FAT32", exfat: "exFAT", ntfs: "NTFS", ext4: "ext4",
  btrfs: "Btrfs", xfs: "XFS", iso9660: "ISO 9660"
}

function formatBytes(bytes) {
  let n = Number(bytes)
  if (!Number.isFinite(n) || n <= 0) return "0 B"
  let i = 0
  while (n >= 1000 && i < BYTE_UNITS.length - 1) {
    n /= 1000
    i++
  }
  const digits = n >= 100 || i === 0 ? Math.round(n) : n.toFixed(1)
  return `${digits} ${BYTE_UNITS[i]}`
}

function parseDrives(raw) {
  try {
    const parsed = JSON.parse(String(raw || "").trim() || "[]")
    return Array.isArray(parsed) ? parsed : []
  } catch (err) {
    console.error("usb-storage list parse failed:", err)
    return []
  }
}

function primaryPartition(drive) {
  const parts = drive && drive.partitions ? drive.partitions : []
  for (let i = 0; i < parts.length; i++)
    if (parts[i].mountpoint) return parts[i]
  return parts.length > 0 ? parts[0] : null
}

function driveTitle(drive) {
  const part = primaryPartition(drive)
  if (part && part.label) return part.label
  return `${formatBytes(drive.size)} USB Drive`
}

function driveSubtitle(drive) {
  const usb = drive.usb || {}
  const seen = {}
  const words = []
  const candidates = [usb.manufacturer, usb.product, drive.vendor, drive.model]
  for (let i = 0; i < candidates.length; i++) {
    const w = String(candidates[i] || "").trim()
    if (!w || seen[w.toLowerCase()]) continue
    seen[w.toLowerCase()] = true
    words.push(w)
  }
  return words.join(" ")
}

function speedLabel(mbps) {
  switch (Number(mbps)) {
  case 1.5: return "USB 1.0 · 1.5 Mbps"
  case 12: return "USB 1.1 · 12 Mbps"
  case 480: return "USB 2.0 · 480 Mbps"
  case 5000: return "USB 3.2 Gen 1 · 5 Gbps"
  case 10000: return "USB 3.2 Gen 2 · 10 Gbps"
  case 20000: return "USB 3.2 Gen 2x2 · 20 Gbps"
  default: return mbps ? `${mbps} Mbps` : "Unknown"
  }
}

function runningSlow(drive) {
  const usb = drive.usb || {}
  return parseFloat(usb.version) >= 3 && Number(usb.speed) > 0 && Number(usb.speed) < 5000
}

function fsLabel(fstype) {
  return FS_NAMES[fstype] || String(fstype || "—")
}

function usedFraction(part) {
  if (!part || !part.size || part.used === null || part.used === undefined) return 0
  return Math.max(0, Math.min(1, Number(part.used) / Number(part.size)))
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    formatBytes: formatBytes,
    parseDrives: parseDrives,
    primaryPartition: primaryPartition,
    driveTitle: driveTitle,
    driveSubtitle: driveSubtitle,
    speedLabel: speedLabel,
    runningSlow: runningSlow,
    fsLabel: fsLabel,
    usedFraction: usedFraction
  }
}
